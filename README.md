# CESM-LE Ocean Downscaling Pipeline

This repository contains the workflow and batch scripts used to build
downscaled ocean products by combining CESM Large Ensemble ocean anomalies with
a GLORYS historical baseline.

The repository itself is intentionally lightweight: it stores orchestration
scripts, helper files, and documentation, while the actual NetCDF inputs,
intermediate products, and final outputs live on HPC systems and shared
filesystems.

## What This Project Does

At a high level, this project:

1. downloads or stages CESM-LE ocean variables and GLORYS ocean data on cluster
   storage;
2. converts GLORYS daily fields into monthly means and a baseline climatology;
3. horizontally regrids CESM fields to a regular grid;
4. vertically interpolates CESM fields onto GLORYS depth levels;
5. computes CESM member-level climatologies and future-minus-baseline deltas;
6. remaps CESM deltas to the GLORYS 0.05 degree grid; and
7. adds those anomalies to the GLORYS baseline climatology to create
   downscaled products for future time windows.

The core scientific idea implemented here is:

- `Downscaled field = GLORYS baseline climatology + CESM future anomaly`

## Project Structure

```text
cesmle-ocn-fetch/
├── data/                           # Tracked lightweight data layout for fetch workflows
│   ├── ipcc_esgf_wget/             # ESGF/IPCC-generated wget shell scripts
│   ├── manifests/                  # Parsed CSV manifests from wget scripts
│   └── downloads/                  # Download destination for fetched files
├── docs/                           # Reference files used during setup/planning
│   ├── CMIP6_MIP_tables.xlsx       # Variable/table reference workbook
│   └── aws-cesm1-le.csv            # CESM-related reference table
├── legacy/                         # Old outputs/examples kept outside the main workflow
│   └── *.nc                        # Example downscaled/anomaly/climatology NetCDF files
├── logs/                           # Slurm stdout/stderr targets (ignored by git)
├── scripts/                        # Main automation layer for the pipeline
│   ├── bash/                       # Download, fetch, and utility shell scripts
│   │   ├── download_cesmle*.sh     # CESM-LE download helpers
│   │   ├── download_GLORYS_parallel.sh
│   │   ├── process_esgf_wget_scripts.sh
│   │   ├── bgc_monthly_download.slurm.sh
│   │   └── z_cesm1_temp.sh
│   ├── core/                       # New reusable processing workers
│   │   └── temporal_aggregate_regrid.slurm.sh
│   ├── runners/                    # New dataset-specific job submitters
│   │   ├── global_ocean_biogeochemistry_hindcast/
│   │   │   └── run_temporal_aggregate_regrid.sh
│   │   ├── cesm/
│   │   ├── glorys/
│   │   └── other_model/
│   ├── slurm/                      # Existing production workflow scripts
│   │   ├── regrid_cesm_pop_1deg*.sh
│   │   ├── cesm_vertical_regrid.slurm.sh
│   │   ├── glorys_monthly_0p05.slurm.sh
│   │   ├── glorys_window_climatology.slurm.sh
│   │   ├── cesm_window_climatologies.slurm.sh
│   │   ├── cesm_member_deltas_0p05.slurm.sh
│   │   ├── cesm_add_to_glorys_downscale.slurm.sh
│   │   └── run_*.sh                # Submission wrappers for selected variables/jobs
│   └── legacy/                     # Reserved for older scripts as they are migrated
├── .gitignore                      # Protects large data, NetCDFs, logs, and temp files
├── LICENSE
└── README.md                       # Project documentation
```

## Repository Philosophy

This repository is not a self-contained local analysis package. It is a
cluster-oriented workflow repository.

That means:

- the code assumes access to Slurm;
- large data are expected to exist on HPC/shared filesystems, not in git;
- most paths are hard-coded for cluster environments;
- local checkout is mainly for editing scripts and documentation; and
- seeing "no data" locally is expected and not a problem.

## Expected Storage Layout On Cluster Systems

The scripts assume one or more cluster filesystems with layouts similar to:

```text
/home/sandbox-sparc/cesmle-ocn-fetch/       # repo checkout on cluster
/home/sandbox-sparc/cesmle-ocn-fetch/cesm/  # staged CESM raw files
/home/sandbox-sparc/cesmle-ocn-fetch/glorys12v1/
/home/SB5/                                  # large shared output area
/scratch/sparc/<user>/                      # scratch space for temp/regridding
```

Common output locations referenced in the scripts include:

- `/home/SB5/glorys12v1_monthly_0p05`
- `/home/SB5/rcp85/<VAR>`
- `/home/SB5/downscaled_rcp85/<GLORYS_VAR>`
- `/home/SB5/tmp`

Because these paths are embedded in the job scripts, moving the pipeline to a
new machine usually requires path editing before execution.

## Main Variables In The Workflow

### CESM variables

- `TEMP`
- `SALT`
- `O2`
- `UVEL`

### GLORYS variables

- `thetao`
- `so`
- `uo`
- `vo`
- `mlotst`
- `zos`
- `bottomT`

### Variable mapping used in the final downscaling step

- `TEMP -> thetao`
- `SALT -> so`
- `UVEL -> uo`

`O2` appears in earlier CESM preprocessing/climatology steps, but it is not
currently included in the final GLORYS-addition downscaling script.

## Time Windows Used By The Pipeline

The scripts consistently use these windows:

- baseline: `2006-01` to `2014-12`
- mid-century future: `2050-01` to `2060-12`
- late-century future: `2090-01` to `2100-12`

For historical raw CESM inputs, the horizontal regridding scripts also refer to
the historical span:

- historical CESM: `1920-01` to `2005-12`

## End-To-End Workflow

## 1. Raw data acquisition

Older download helpers in [scripts/bash](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/bash)
handle remote data acquisition.

CESM download scripts:

- probe NCAR/RDA-hosted CESM-LE ocean monthly files;
- support historical and RCP8.5-style scenario file naming;
- can work by directory scraping or by probing expected file names;
- support resumable downloads and retry logic in some versions; and
- write manifests of discovered files.

GLORYS download script:

- uses the `copernicusmarine` CLI;
- downloads daily GLORYS12v1 files by month;
- organizes them by `year/month`;
- can flatten nested output directories; and
- writes monthly manifests.

These scripts are useful for data staging, but the current production
downscaling flow is driven primarily by the scripts in
[scripts/slurm](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm), while
new reusable utilities are beginning to be added under
[scripts/core](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core) and
[scripts/runners](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners).

## 2. CESM horizontal regridding to 1 degree

Primary scripts:

- [scripts/slurm/regrid_cesm_pop_1deg.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/regrid_cesm_pop_1deg.slurm.sh)
- [scripts/slurm/regrid_cesm_pop_1deg_homeout.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/regrid_cesm_pop_1deg_homeout.slurm.sh)

Purpose:

- reads raw CESM ocean files;
- selects one variable at a time;
- remaps to a regular `360 x 180` global grid using `cdo remapbil`;
- stores per-file regridded outputs in `parts/`; and
- for RCP85 files, merges split time chunks into `merged/` products.

Important details:

- controlled by environment variables `SCEN` and `VAR`;
- accepts `hist` and `rcp85` scenarios;
- uses conservative parallelism to avoid I/O and HDF5 instability; and
- includes free-space checks before large jobs begin.

The `run_regrid*.sh` scripts are lightweight submitter wrappers that choose
variables and job ordering.

## 3. GLORYS monthly means at 0.05 degree

Primary script:

- [scripts/slurm/glorys_monthly_0p05.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/glorys_monthly_0p05.slurm.sh)

Purpose:

- reads daily GLORYS files for a single variable and year;
- merges daily files within each month;
- computes monthly means with `cdo monmean`; and
- remaps monthly results to a regular global `0.05 degree` lon/lat grid.

Output organization:

- outputs live under `/home/SB5/glorys12v1_monthly_0p05/<VAR>/parts`
- one output file is created per month

This step provides the monthly baseline products used later to build the GLORYS
climatology.

## 4. GLORYS baseline climatology

Primary script:

- [scripts/slurm/glorys_window_climatology.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/glorys_window_climatology.slurm.sh)

Purpose:

- reads all monthly GLORYS products from `2006-01` through `2014-12`;
- merges them in time; and
- computes a single mean field over the full window with `cdo timmean`.

This is described in the script as a "Bio-ORACLE-style" climatology:

- one mean over all monthly values in the baseline window;
- one output file per variable; and
- no monthly climatology cycle is produced here.

Result:

- `glorys12v1_<VAR>_clim_2006-2014.nc`

## 5. CESM vertical interpolation onto GLORYS depth levels

Primary script:

- [scripts/slurm/cesm_vertical_regrid.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/cesm_vertical_regrid.slurm.sh)

Purpose:

- reads CESM files already regridded and merged;
- extracts/defines a GLORYS vertical axis template;
- converts CESM `z_t` depth units from centimeters to meters; and
- vertically interpolates CESM data onto GLORYS depth levels using `cdo intlevel`.

Important implementation detail:

- the script builds shared helper files under `/home/SB5/tmp`:
  - `glorys_zaxis.txt`
  - `cesm_zaxis_m.txt`

Result:

- vertically aligned CESM files under `/home/SB5/rcp85/<VAR>/on_glorys`

## 6. CESM member climatologies

Primary script:

- [scripts/slurm/cesm_window_climatologies.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/cesm_window_climatologies.slurm.sh)

Purpose:

- reads CESM files already interpolated onto GLORYS levels;
- computes one mean per ensemble member for each time window; and
- writes separate baseline, 2050s, and 2090s climatology files.

Outputs per member:

- `_clim_2006-2014.nc`
- `_clim_2050-2060.nc`
- `_clim_2090-2100.nc`

This is also a full-window mean approach rather than a monthly climatology
approach.

## 7. CESM future-minus-baseline deltas and remap to 0.05 degree

Primary script:

- [scripts/slurm/cesm_member_deltas_0p05.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/cesm_member_deltas_0p05.slurm.sh)

Purpose:

- pairs each future CESM member climatology with the matching baseline file;
- computes anomalies as `future - baseline` with `cdo sub`; and
- remaps those anomalies to the GLORYS `0.05 degree` grid.

Outputs:

- raw member anomalies in `member_deltas/`
- remapped anomalies in `member_deltas_0p05/`

Time windows processed:

- `2050-2060 minus 2006-2014`
- `2090-2100 minus 2006-2014`

## 8. Final downscaling by adding CESM anomalies to GLORYS

Primary script:

- [scripts/slurm/cesm_add_to_glorys_downscale.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/cesm_add_to_glorys_downscale.slurm.sh)

Purpose:

- reads the GLORYS baseline climatology;
- reads CESM member anomaly fields already remapped to `0.05 degree`;
- adjusts the shallowest GLORYS levels in the anomaly field; and
- adds the anomaly to the GLORYS baseline to generate a downscaled future field.

Important scientific/technical detail:

- the script fills the first `4` shallow GLORYS levels using the first valid
  CESM-derived anomaly layer, described in the code as the level near
  `5.078 m`;
- this is done before the anomaly is added to the baseline; and
- output is written one file per member per future window.

Outputs look like:

- `<member>_downscaled_thetao_2050-2060.nc`
- `<member>_downscaled_thetao_2090-2100.nc`

The example NetCDF files in [legacy](/Users/ibrito/Desktop/cesmle-ocn-fetch/legacy)
match this final stage and are useful as reference artifacts.

## Main Scripts By Role

### New generalized script structure

The repository is in transition toward a more reusable script layout:

- [scripts/core](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core)
  contains reusable worker scripts that perform one core operation.
- [scripts/runners](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners)
  contains dataset-specific submitters that configure variables, paths, and
  years, then submit jobs to the core workers.
- [scripts/slurm](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm)
  still contains the older production workflow scripts and runners that remain
  in active use.
- [scripts/legacy](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/legacy)
  is reserved for older scripts that may be moved out of the active path later.

Current example in the new structure:

- generic worker:
  [temporal_aggregate_regrid.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/temporal_aggregate_regrid.slurm.sh)
- dataset-specific runner:
  [run_temporal_aggregate_regrid.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/global_ocean_biogeochemistry_hindcast/run_temporal_aggregate_regrid.sh)

The generic temporal aggregation worker supports:

- daily inputs that need monthly averaging before regridding;
- monthly inputs that should skip temporal aggregation and only be regridded; and
- auto-detection of those cases based on the number of files in each month.

### Existing production workflow scripts

Located in [scripts/slurm](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm):

- `regrid_cesm_pop_1deg*.slurm.sh`
- `cesm_vertical_regrid.slurm.sh`
- `glorys_monthly_0p05.slurm.sh`
- `glorys_window_climatology.slurm.sh`
- `cesm_window_climatologies.slurm.sh`
- `cesm_member_deltas_0p05.slurm.sh`
- `cesm_add_to_glorys_downscale.slurm.sh`

### Job submission wrappers

Also in [scripts/slurm](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm):

- `run_regrid.sh`
- `run_regrid_deps.sh`
- `run_regrid_homeout.sh`
- `run_glorys_monthly_0p05.sh`
- `run_glorys_window_climatology.sh`
- `run_cesm_vertical_regrid.sh`
- `run_cesm_window_climatologies.sh`
- `run_cesm_member_deltas_0p05.sh`
- `run_cesm_add_to_glorys_downscale.sh`

These are convenience scripts for selecting variables and submitting one or
more jobs with `sbatch`.

### Download and utility scripts

Located in [scripts/bash](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/bash):

- `download_cesmle.sh`
- `download_cesmle_list_parallel.sh`
- `download_cesmle_list_parallel-hist.sh`
- `download_cesmle_list_parallel-proj.sh`
- `download_cesmle_list_and_get.sh`
- `download_GLORYS_parallel.sh`
- `bgc_monthly_download.slurm.sh`
- `process_esgf_wget_scripts.sh`

These are useful references for data acquisition history and staging logic, but
the main end-to-end downscaling logic lives under `scripts/slurm/`.

## Typical Execution Order

For the current production-style workflow, the logical order is:

1. stage CESM and GLORYS data on cluster filesystems;
2. run GLORYS monthly processing at `0.05 degree`;
3. build the GLORYS baseline climatology;
4. regrid CESM horizontally to `1 degree`;
5. merge CESM scenario chunks when needed;
6. vertically interpolate CESM onto GLORYS depth levels;
7. compute CESM member climatologies;
8. compute CESM deltas and remap them to `0.05 degree`; and
9. add CESM anomalies to GLORYS to generate downscaled outputs.

## Software Assumptions

The scripts assume the cluster environment provides:

- `bash`
- `sbatch` and `squeue` from Slurm
- `cdo`
- `curl`
- `find`, `grep`, `awk`, `sed`, `xargs`
- `python3`
- `xarray` for the final anomaly-addition step
- optionally `copernicusmarine` for GLORYS downloads

Some scripts also assume:

- `conda` environments may be available;
- `SLURM_TMPDIR` may exist on compute nodes; and
- NetCDF/HDF5 behavior may require conservative parallelism.

## Restartability And Safety Features

Several scripts are written to be restart-friendly. Common patterns include:

- skip outputs that already exist;
- write to temporary files before moving final outputs into place;
- separate `parts/`, `merged/`, and `tmp/` directories;
- preflight free-space checks on scratch or temp filesystems; and
- conservative CPU settings to reduce file I/O crashes.

This is especially important because these jobs operate on very large NetCDF
files in shared HPC environments.

## Important Limitations

Before reusing or extending the pipeline, keep in mind:

- many paths are hard-coded for specific cluster environments;
- this repository does not include a portable config system;
- the current workflow is strongly tied to Slurm;
- local execution without the cluster data layout will not work out of the box;
- some scripts represent older experiments or transitional versions; and
- the README documents the workflow as currently inferred from the scripts, not
  from a separate formal methods document.

## Notes On Git Tracking

The repository is configured to avoid committing large data and generated
artifacts. The `.gitignore` excludes, among other things:

- NetCDF files (`*.nc`)
- partial download files (`*.part`)
- logs
- large data directories such as `cesm/`, `glorys12v1/`, and `legacy/`

That is why the working repository can appear almost empty even though the full
pipeline is active on the cluster.
