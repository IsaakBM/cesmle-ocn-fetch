# CESM-LE Ocean Downscaling Pipeline

This repository contains HPC batch workflows for preparing, vertically matching,
and computing climatologies from ocean model products used in downscaling
workflows.

The repository itself is lightweight. It stores scripts, helpers, and
documentation. The actual NetCDF inputs, intermediate products, and final
outputs live on cluster filesystems such as `/home/SB5`,
`/home/sandbox-sparc`, and scratch space.

## What This Repository Does

At a high level, the repository now supports three reusable processing stages:

1. monthly preparation and horizontal harmonization
2. vertical interpolation to a GLORYS reference grid
3. climatology windows from either monthly files or long time-series files

These stages sit inside a broader downscaling pipeline. After climatologies are
computed, later steps can still include:

4. anomalies and deltas between baseline and future climatology windows
5. addition of anomalies to a historical baseline
6. final downscaled products

Those stages are reused across different dataset families:

- GLORYS
- CESM
- Global Ocean Biogeochemistry Hindcast
- IPCC/ESGF products

The key point is that the newer code organization is based on **data structure**
and **processing operation**, not on one script per dataset.

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
├── logs/                           # Slurm stdout/stderr targets
├── scripts/
│   ├── bash/                       # Download, fetch, and utility shell scripts
│   │   ├── download_cesmle*.sh
│   │   ├── download_GLORYS_parallel.sh
│   │   ├── process_esgf_wget_scripts.sh
│   │   ├── process_esgf_wget_scripts_run_example.txt
│   │   ├── bgc_monthly_download.slurm.sh
│   │   └── z_cesm1_temp.sh
│   ├── core/                       # Reusable processing workers
│   │   ├── temporal_aggregate_regrid.slurm.sh
│   │   ├── vertical_interpolate_to_reference.slurm.sh
│   │   ├── climatology_window_from_monthly_files.slurm.sh
│   │   ├── climatology_window_from_timeseries.slurm.sh
│   │   ├── delta_from_climatologies.slurm.sh
│   │   └── add_anomaly_to_baseline.slurm.sh
│   ├── runners/                    # Dataset-specific job submitters
│   │   ├── global_ocean_biogeochemistry_hindcast/
│   │   │   ├── run_temporal_aggregate_regrid.sh
│   │   │   ├── run_vertical_interpolate_to_reference.sh
│   │   │   └── run_climatology_window.sh
│   │   ├── ipcc_esgf/
│   │   │   ├── run_temporal_aggregate_regrid.sh
│   │   │   ├── run_vertical_interpolate_to_reference.sh
│   │   │   ├── run_climatology_window.sh
│   │   │   └── run_delta_from_climatologies.sh
│   │   ├── ipcc_esgf_to_hindcast/
│   │   │   └── run_add_anomaly_to_baseline.sh
│   │   ├── cesm/
│   │   ├── glorys/
│   │   └── other_model/
│   ├── slurm/                      # Older production scripts still kept in place
│   └── legacy/                     # Reserved for older scripts as they are migrated
├── .gitignore
├── LICENSE
└── README.md
```

## Repository Philosophy

This is a cluster-oriented workflow repository.

That means:

- the code assumes Slurm;
- large data are expected on HPC/shared filesystems, not in git;
- local checkout is mainly for editing scripts and docs;
- many paths are cluster-specific;
- empty local data directories are expected and normal.

## Main Script Organization

The newer structure is organized around **what kind of operation is being
performed**.

### `scripts/core/`

Reusable worker scripts. These do the actual processing.

- [temporal_aggregate_regrid.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/temporal_aggregate_regrid.slurm.sh)
  - generic monthly preparation and horizontal harmonization
  - supports two input layouts:
    - `year_month`
    - `timeseries`
  - supports:
    - daily input that must be aggregated to monthly
    - already-monthly input that skips aggregation
    - direct regridding/harmonization to a target grid

- [vertical_interpolate_to_reference.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/vertical_interpolate_to_reference.slurm.sh)
  - generic vertical interpolation to a reference vertical grid
  - can reuse or create shared z-axis descriptors
  - supports source-unit conversion such as `cm -> m`
  - writes vertically matched outputs such as `on_glorys/`

- [climatology_window_from_monthly_files.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/climatology_window_from_monthly_files.slurm.sh)
  - computes a climatology from many monthly files
  - intended for layouts like one file per month in a `parts/` directory

- [climatology_window_from_timeseries.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/climatology_window_from_timeseries.slurm.sh)
  - computes a climatology from one long time-series file or a few chunked
    time-series files
  - merges chunks when needed before selecting the target window

- [delta_from_climatologies.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/delta_from_climatologies.slurm.sh)
  - computes `future climatology - baseline climatology`
  - can optionally regrid the resulting delta to a target grid
  - keeps the subtraction logic generic while runners decide when regridding
    is part of the dataset workflow

- [add_anomaly_to_baseline.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/add_anomaly_to_baseline.slurm.sh)
  - reads one baseline climatology and one anomaly/delta file
  - dynamically fills only the top anomaly levels that are missing, using the
    first deeper level that contains valid values
  - adds anomaly to baseline to create the downscaled future field
  - writes the native output
  - can optionally regrid the final downscaled product to another grid

### `scripts/runners/`

Dataset-specific submitters. These define:

- variables
- scenarios
- windows
- input/output paths
- dataset-specific assumptions

and then call the generic workers in `scripts/core/` using `sbatch`.

### `scripts/slurm/`

Older production scripts are still kept here and remain useful references.
These are not removed yet because they document the original working workflows
and still help validate the newer abstractions.

## Workflow Logic

The current logic is easiest to understand in three immediate processing layers,
followed by the later downscaling stages.

### 1. Monthly Preparation / Grid Harmonization

This stage creates or prepares monthly files on a common horizontal grid.

Use:

- [temporal_aggregate_regrid.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/temporal_aggregate_regrid.slurm.sh)

This stage is the generalized version of what older scripts such as
[glorys_monthly_0p05.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/glorys_monthly_0p05.slurm.sh)
were doing.

Typical outputs live in `parts/`.

Examples:

- Hindcast monthly outputs:
  `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/<var>/parts/*.nc`
- IPCC/ESGF regridded monthly time-series:
  `/home/SB5/ipcc_esgf_monthly_1deg/<scenario>/<var>/parts/*.nc`

Important note:

- the temporal regrid worker can run with `METHOD=auto`
- in auto mode it reads the source `gridtype` from the file metadata
- curvilinear or unstructured grids use `remapdis`
- regular lon/lat grids use `remapbil`
- this matters for some native-grid ocean products where bilinear remapping
  introduces seam artifacts that then propagate into later steps

### 2. Vertical Interpolation To GLORYS Levels

This stage takes horizontally harmonized files and interpolates them onto the
GLORYS vertical grid.

Use:

- [vertical_interpolate_to_reference.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/vertical_interpolate_to_reference.slurm.sh)

Typical outputs live in `on_glorys/`.

Examples:

- Hindcast:
  `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/<var>/on_glorys/*.nc`
- IPCC/ESGF:
  `/home/SB5/ipcc_esgf_monthly_1deg/<scenario>/<var>/on_glorys/*.nc`

This stage is the generalized version of the old CESM vertical-matching idea
implemented in
[cesm_vertical_regrid.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/cesm_vertical_regrid.slurm.sh).

### 3. Climatology Windows

This stage produces one mean over a requested time window from monthly data.

There are two cases.

#### Many monthly files

Use:

- [climatology_window_from_monthly_files.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/climatology_window_from_monthly_files.slurm.sh)

This is the GLORYS-style or hindcast-style case:

- one file per month
- many files in `parts/`
- then merge and compute `timmean`

#### Long monthly time-series files

Use:

- [climatology_window_from_timeseries.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/climatology_window_from_timeseries.slurm.sh)

This is the CESM-style or IPCC/ESGF-style case:

- one long monthly time-series file
- or a few chunked monthly time-series files
- merge chunks if needed
- select the date window
- compute `timmean`

### 4. Later Downscaling Stages

The newer generalized scripts now cover the preparation and climatology parts of
the workflow, but the repository still includes the later downscaling logic that
follows after climatologies are available.

Those later stages include:

- future-minus-baseline anomalies or deltas
- remapping of anomaly products where needed
- addition of anomalies to a baseline field
- final downscaled output generation

In the newer generalized structure, those later-stage operations are now
represented by:

- [delta_from_climatologies.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/delta_from_climatologies.slurm.sh)
- [add_anomaly_to_baseline.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/add_anomaly_to_baseline.slurm.sh)

The original CESM-to-GLORYS production scripts for these later stages are still
kept in [scripts/slurm](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm),
including:

- [cesm_member_deltas_0p05.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/cesm_member_deltas_0p05.slurm.sh)
- [cesm_add_to_glorys_downscale.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/slurm/cesm_add_to_glorys_downscale.slurm.sh)

So the generalized `core/` plus `runners/` structure should be read as the
full pipeline structure, with the newer generalized code increasingly covering
the later anomaly/delta/downscaling steps as well.

## Dataset Mapping

### GLORYS

Typical older logic:

1. monthly means at `0.05°`
2. baseline climatology from monthly files

Closest modern abstraction:

- monthly prep/harmonization:
  [temporal_aggregate_regrid.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/temporal_aggregate_regrid.slurm.sh)
- climatology from monthly files:
  [climatology_window_from_monthly_files.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/climatology_window_from_monthly_files.slurm.sh)

### CESM

Typical older logic:

1. horizontal regrid
2. vertical interpolation to GLORYS levels
3. climatology windows from member time-series files
4. deltas between future and baseline climatologies
5. addition of deltas to the GLORYS baseline

Closest modern abstraction:

- vertical interpolation:
  [vertical_interpolate_to_reference.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/vertical_interpolate_to_reference.slurm.sh)
- climatology from time-series files:
  [climatology_window_from_timeseries.slurm.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/core/climatology_window_from_timeseries.slurm.sh)

### Global Ocean Biogeochemistry Hindcast

Current logic:

1. monthly inputs already organized by `YEAR/MONTH`
2. prepare/harmonize monthly outputs at `0.25 x 0.25`
3. vertically interpolate to GLORYS levels
4. later compute climatology windows

Relevant runners:

- [run_temporal_aggregate_regrid.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/global_ocean_biogeochemistry_hindcast/run_temporal_aggregate_regrid.sh)
- [run_vertical_interpolate_to_reference.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/global_ocean_biogeochemistry_hindcast/run_vertical_interpolate_to_reference.sh)
- [run_climatology_window.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/global_ocean_biogeochemistry_hindcast/run_climatology_window.sh)

Important note:

- `spco2` is a surface field and is not appropriate for the vertical
  interpolation step.

### IPCC / ESGF

Current logic:

1. download ESGF/IPCC files
2. reorganize by scenario and variable
3. regrid monthly time-series to `1 x 1`
4. vertically interpolate to GLORYS levels
5. compute climatology windows from the vertically matched products
6. compute future-minus-baseline deltas
7. optionally regrid deltas to `0.25 x 0.25`

Expected input organization:

```text
/home/SB5/ipcc_esgf_downloads/
├── historical/
│   ├── chl/
│   └── o2/
└── ssp585/
    ├── chl/
    └── o2/
```

Regridded monthly products are organized as:

```text
/home/SB5/ipcc_esgf_monthly_1deg/
├── historical/
│   └── <var>/
│       ├── parts/
│       ├── on_glorys/
│       └── clim_windows/
└── ssp585/
    └── <var>/
        ├── parts/
        ├── on_glorys/
        ├── clim_windows/
        ├── delta_windows/
        └── delta_windows_0p25/
```

Operational sequence for the current IPCC branch:

1. run [run_temporal_aggregate_regrid.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh)
   - reads `/home/SB5/ipcc_esgf_downloads/<scenario>/<var>/`
   - writes `/home/SB5/ipcc_esgf_monthly_1deg/<scenario>/<var>/parts/`
   - uses `METHOD=auto`
   - auto-selects `remapdis` for curvilinear/unstructured sources and
     `remapbil` for regular lon/lat sources

2. run [run_vertical_interpolate_to_reference.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh)
   - reads `/parts/`
   - writes `/on_glorys/`

3. run [run_climatology_window.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf/run_climatology_window.sh)
   - reads `/on_glorys/`
   - writes `/clim_windows/`
   - historical baseline window: `2006-2014`
   - future windows: `2050-2060`, `2090-2100`

4. run [run_delta_from_climatologies.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh)
   - computes:
     `ssp585 future climatology - historical 2006-2014 climatology`
   - writes `/delta_windows/`
   - also writes `/delta_windows_0p25/` when delta regridding is enabled

Relevant runners:

- [run_temporal_aggregate_regrid.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh)
- [run_vertical_interpolate_to_reference.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh)
- [run_climatology_window.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf/run_climatology_window.sh)
- [run_delta_from_climatologies.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh)

### IPCC / ESGF To Hindcast Downscaling

Current logic:

1. use hindcast climatology at `0.25 x 0.25` as the baseline
2. use IPCC/ESGF deltas at `0.25 x 0.25` as the anomaly field
3. dynamically fill only the top missing anomaly layers
4. add the filled anomaly to the baseline
5. write the native downscaled output at `0.25 x 0.25`
6. optionally regrid the downscaled product to `0.05 x 0.05`

Expected inputs:

- hindcast baseline climatologies:
  `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/<var>/clim_windows/*.nc`
- IPCC/ESGF deltas already regridded to `0.25 x 0.25`:
  `/home/SB5/ipcc_esgf_monthly_1deg/ssp585/<var>/delta_windows_0p25/*.nc`

Downscaled outputs are organized as:

```text
/home/SB5/downscaled_rcp85/
├── chl/
│   ├── 0p25/
│   │   ├── 2050-2060/
│   │   └── 2090-2100/
│   ├── 0p05/
│   │   ├── 2050-2060/
│   │   └── 2090-2100/
│   └── tmp_add/
└── o2/
    ├── 0p25/
    │   ├── 2050-2060/
    │   └── 2090-2100/
    ├── 0p05/
    │   ├── 2050-2060/
    │   └── 2090-2100/
    └── tmp_add/
```

Operational sequence for this final stage:

1. run [run_add_anomaly_to_baseline.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline.sh)
   - reads hindcast baseline climatology files from `clim_windows/`
   - reads IPCC/ESGF delta files from `delta_windows_0p25/`
   - fills top missing anomaly layers dynamically
   - writes the native downscaled output at `0.25`
   - also writes a `0.05` product using `remapdis`

Important note:

- the top-layer fill is now dynamic rather than hard-coded
- if only the first anomaly level is missing, only that level is filled
- if the first several anomaly levels are missing, all missing top levels are
  filled from the first deeper level that contains valid values
- this generalizes the older CESM-to-GLORYS logic, where the top 4 levels were
  always replaced from a fixed deeper layer

Relevant runner:

- [run_add_anomaly_to_baseline.sh](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline.sh)

## Download And Utility Scripts

Located in [scripts/bash](/Users/ibrito/Desktop/cesmle-ocn-fetch/scripts/bash):

- `download_cesmle.sh`
- `download_cesmle_list_parallel.sh`
- `download_cesmle_list_parallel-hist.sh`
- `download_cesmle_list_parallel-proj.sh`
- `download_cesmle_list_and_get.sh`
- `download_GLORYS_parallel.sh`
- `bgc_monthly_download.slurm.sh`
- `process_esgf_wget_scripts.sh`

These are for acquisition, staging, and utilities. They are not the main
scientific processing workers.

## Example Output Patterns

### Monthly preparation outputs

Examples:

- hindcast:
  `global_ocean_biogeochemistry_hindcast_chl_200601.monmean.grid_0p25_global.nc`
- IPCC/ESGF:
  `chl_Omon_CNRM-ESM2-1_historical_r1i1p1f2_gn_200001-201412.grid_1deg_global.nc`

### Vertical interpolation outputs

Examples:

- hindcast:
  `<monthly_file>_on_glorys.nc`
- IPCC/ESGF:
  `<timeseries_file>_on_glorys.nc`

### Climatology outputs

Examples:

- monthly-files climatology:
  `global_ocean_biogeochemistry_hindcast_chl_clim_2006-2014.nc`
- time-series climatology:
  `ipcc_esgf_historical_chl_clim_2006-2014.nc`
  `ipcc_esgf_ssp585_chl_clim_2050-2060.nc`
  `ipcc_esgf_ssp585_chl_clim_2090-2100.nc`

### Delta outputs

Examples:

- raw delta:
  `ipcc_esgf_ssp585_chl_delta_2050-2060_minus_2006-2014.nc`
- regridded delta:
  `ipcc_esgf_ssp585_chl_delta_2050-2060_minus_2006-2014.grid_0p25_global.nc`

### Downscaled outputs

Examples:

- native `0.25` downscaled output:
  `ipcc_esgf_to_hindcast_chl_downscaled_2050-2060.nc`
- regridded `0.05` downscaled output:
  `ipcc_esgf_to_hindcast_chl_downscaled_2050-2060_grid_0p05_global.nc`

## Expected Cluster Paths

Common paths used in the current workflows include:

- `/home/sandbox-sparc/cesmle-ocn-fetch`
- `/home/sandbox-sparc/cesmle-ocn-fetch/bgc_monthly_0p25`
- `/home/SB5/glorys12v1_monthly_0p05`
- `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25`
- `/home/SB5/ipcc_esgf_downloads`
- `/home/SB5/ipcc_esgf_monthly_1deg`
- `/home/SB5/rcp85`
- `/home/SB5/downscaled_rcp85`
- `/home/SB5/tmp`

Because these are embedded in scripts and runners, moving the workflow to a new
system requires path updates.

## Software Assumptions

The scripts assume the cluster environment provides:

- `bash`
- `sbatch`, `squeue`
- `cdo`
- `curl`
- `find`, `grep`, `awk`, `sed`, `xargs`
- `python3` for some older scripts
- NetCDF support compatible with CDO

## Important Current Distinctions

To avoid confusion:

- `temporal_aggregate_regrid.slurm.sh` is **not** a climatology script.
  It prepares monthly data and harmonizes grids.

- when `temporal_aggregate_regrid.slurm.sh` runs with `METHOD=auto`, it chooses
  the remap operator from the source `gridtype` metadata, not from the ESGF
  filename label alone.

- `climatology_window_from_monthly_files.slurm.sh` and
  `climatology_window_from_timeseries.slurm.sh` **are** climatology scripts.
  They compute period means from monthly data.

- `vertical_interpolate_to_reference.slurm.sh` is the step that creates
  `on_glorys/` outputs before vertically matched climatologies are computed.

- `delta_from_climatologies.slurm.sh` computes future-minus-baseline anomaly
  products; it does not add them to a baseline.

- `add_anomaly_to_baseline.slurm.sh` is the addition/downscaling step.
  It combines a baseline climatology with an anomaly/delta field and can also
  produce an optional remapped final product.

- The downscaling part of the overall workflow still continues after
  climatologies. Climatologies are not the final product; they are the inputs to
  later anomaly, delta, and downscaling stages.
