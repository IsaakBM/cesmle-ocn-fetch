# Ocean Downscaling And Delivery Pipeline

<img src="docs/assets/save-the-blue-five-logo.png" alt="Save The Blue Five logo" width="260">

This repository contains HPC batch workflows for preparing, vertically matching,
downscaling, organizing, and exporting ocean model products across multiple
workflow families.

The repository itself is lightweight. It stores scripts, helpers, and
documentation. The actual NetCDF inputs, intermediate products, and final
outputs live on cluster filesystems such as `/home/SB5`,
`/home/sandbox-sparc`, and scratch space.

## Read This First

The easiest way to understand the repository is to read it in this order:

1. **Purpose and architecture**
   - what the repository produces
   - how `core`, `runners`, and `tools` divide responsibilities
2. **Common processing stages**
   - monthly preparation
   - vertical interpolation
   - climatology windows
   - delta and anomaly addition
3. **Workflow families**
   - GLORYS baseline
   - hindcast baseline
   - IPCC/ESGF to hindcast downscaling
   - CESM to GLORYS downscaling
4. **Curated product pipeline**
   - organize final products
   - create fine layers
   - create pelagic layers
   - export parquet / CSV outputs

If you only need the current logic, focus first on:

- [Architecture And Script Roles](#architecture-and-script-roles)
- [Common Processing Stages](#common-processing-stages)
- [Current Workflow Families](#current-workflow-families)
- [Curated Product Pipeline](#curated-product-pipeline)

## Current End-To-End Workflow Map

At the highest level, the repository has two kinds of workflows:

1. **Scientific production workflows**
   - build baseline climatologies
   - build future anomalies or deltas
   - add anomalies to a trusted baseline
   - write final downscaled NetCDF products

2. **Curated delivery workflows**
   - reorganize final NetCDF outputs into delivery trees
   - aggregate depth-layer or pelagic products
   - export delivery-ready parquet or CSV products

The current scientific branches are:

- `glorys/`
  - prepares the GLORYS baseline products
- `global_ocean_biogeochemistry_hindcast/`
  - prepares the hindcast baseline products
- `ipcc_esgf/`
  - prepares IPCC/ESGF monthly products, climatologies, and deltas
- `ipcc_esgf_to_hindcast/`
  - adds IPCC/ESGF deltas to the hindcast baseline
- `cesm_to_glorys/`
  - adds CESM member deltas to the GLORYS baseline

The current curated-product chain is:

1. [run_organize_ocean_downscaling_products.sh](scripts/runners/products/run_organize_ocean_downscaling_products.sh)
2. [run_aggregate_ocean_downscaling_products_fine_layers.sh](scripts/runners/products/run_aggregate_ocean_downscaling_products_fine_layers.sh)
3. [run_aggregate_ocean_downscaling_products_pelagic_layers.sh](scripts/runners/products/run_aggregate_ocean_downscaling_products_pelagic_layers.sh)
4. [run_export_ocean_downscaling_products_layers_to_parquet.sh](scripts/runners/products/run_export_ocean_downscaling_products_layers_to_parquet.sh)
5. [run_export_ocean_downscaling_products_pelagic_to_parquet.sh](scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_parquet.sh)

## Purpose

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

The key point is that the newer code organization is based on:

- **data structure**
- **processing operation**
- and then **dataset-specific runners** that wire those generic pieces together

So the repository is not organized as “one custom script per dataset.”

## Repository Layout

```text
cesmle-ocn-fetch/
├── data/                           # Tracked lightweight data layout for fetch workflows
│   ├── ipcc_esgf_wget/             # ESGF/IPCC-generated wget shell scripts
│   ├── manifests/                  # Parsed CSV manifests from wget scripts
│   └── downloads/                  # Download destination for fetched files
├── docs/                           # Reference files used during setup/planning
│   ├── CMIP6_MIP_tables.xlsx       # Variable/table reference workbook
│   └── aws-cesm1-le.csv            # CESM-related reference table
├── legacy/                         # Archived outputs and pre-refactor workflow code
│   ├── *.nc                        # Example downscaled/anomaly/climatology NetCDF files
│   └── scripts/
│       └── slurm/                  # Archived pre-refactor Slurm workflow scripts
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
│   │   ├── add_anomaly_to_baseline.slurm.sh
│   │   ├── add_anomaly_to_baseline_with_coastal_fill.slurm.sh
│   │   └── add_cesm_members_to_glorys_with_coastal_fill.slurm.sh
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
│   │   │   ├── run_add_anomaly_to_baseline.sh
│   │   │   └── run_add_anomaly_to_baseline_with_coastal_fill.sh
│   │   ├── cesm_to_glorys/
│   │   │   ├── run_temporal_aggregate_regrid.sh
│   │   │   ├── run_vertical_interpolate_to_reference.sh
│   │   │   ├── run_climatology_window.sh
│   │   │   ├── run_delta_from_climatologies.sh
│   │   │   ├── run_add_anomaly_to_baseline.sh
│   │   │   └── run_add_anomaly_to_baseline_with_coastal_fill.sh
│   │   ├── downscaling/
│   │   │   └── run_add_anomaly_to_trusted_baseline_with_coastal_fill.sh
│   │   ├── products/
│   │   │   ├── run_organize_ocean_downscaling_products.sh
│   │   │   ├── run_remap_hindcast_baseline_to_0p05.sh
│   │   │   ├── run_aggregate_ocean_downscaling_products_fine_layers.sh
│   │   │   ├── run_aggregate_ocean_downscaling_products_pelagic_layers.sh
│   │   │   ├── run_split_ocean_downscaling_products_by_depth.sh
│   │   │   ├── run_export_ocean_downscaling_products_bydepth_to_csv.sh
│   │   │   ├── run_export_ocean_downscaling_products_layers_to_parquet.sh
│   │   │   └── run_export_ocean_downscaling_products_pelagic_to_parquet.sh
│   │   ├── glorys/
│   │   │   ├── run_temporal_aggregate_regrid.sh
│   │   │   └── run_climatology_window.sh
│   │   └── other_model/
│   ├── tools/                      # Packaging/export/organization utilities
│   │   ├── organize_ocean_downscaling_products.sh
│   │   ├── remap_hindcast_baseline_to_0p05.sh
│   │   ├── aggregate_ocean_downscaling_products_by_depth_bins.sh
│   │   ├── split_ocean_downscaling_products_by_depth.sh
│   │   ├── export_ocean_downscaling_products_bydepth_to_csv.sh
│   │   └── export_ocean_downscaling_products_to_parquet.sh
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

## Architecture And Script Roles

The newer structure is organized around **what kind of operation is being
performed**.

### `scripts/core/`

Reusable worker scripts. These do the actual processing.

- [temporal_aggregate_regrid.slurm.sh](scripts/core/temporal_aggregate_regrid.slurm.sh)
  - generic monthly preparation and horizontal harmonization
  - supports two input layouts:
    - `year_month`
    - `timeseries`
  - supports:
    - daily input that must be aggregated to monthly
    - already-monthly input that skips aggregation
    - direct regridding/harmonization to a target grid

- [vertical_interpolate_to_reference.slurm.sh](scripts/core/vertical_interpolate_to_reference.slurm.sh)
  - generic vertical interpolation to a reference vertical grid
  - can reuse or create shared z-axis descriptors
  - supports source-unit conversion such as `cm -> m`
  - writes vertically matched outputs such as `on_glorys/`

- [climatology_window_from_monthly_files.slurm.sh](scripts/core/climatology_window_from_monthly_files.slurm.sh)
  - computes a climatology from many monthly files
  - intended for layouts like one file per month in a `parts/` directory
  - can dynamically fill missing top climatology layers from the first deeper
    valid layer in each water column

- [climatology_window_from_timeseries.slurm.sh](scripts/core/climatology_window_from_timeseries.slurm.sh)
  - computes a climatology from one long time-series file or a few chunked
    time-series files
  - merges chunks when needed before selecting the target window

- [delta_from_climatologies.slurm.sh](scripts/core/delta_from_climatologies.slurm.sh)
  - computes `future climatology - baseline climatology`
  - can optionally regrid the resulting delta to a target grid
  - keeps the subtraction logic generic while runners decide when regridding
    is part of the dataset workflow

- [add_anomaly_to_baseline.slurm.sh](scripts/core/add_anomaly_to_baseline.slurm.sh)
  - legacy/simple final addition worker without horizontal coastal repair
  - kept for the non-coastal path and for comparison against the
    coastal-fill variant
  - reads one baseline climatology and one anomaly/delta file
  - first computes baseline plus anomaly
  - then dynamically fills missing top layers in the final output, using the
    first deeper level that contains valid values
  - writes the native output
  - can optionally regrid the final downscaled product to another grid

- [add_anomaly_to_baseline_with_coastal_fill.slurm.sh](scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh)
  - current production final addition/downscaling worker
  - reads one trusted baseline climatology and one anomaly/delta file
  - can remap the anomaly onto the trusted target grid before addition
  - can repair missing anomaly cells only inside the trusted target wet mask
  - currently supports `nearest` and `distance_weighted` anomaly fill methods
  - the current distance-weighted implementation reuses precomputed local
    donor geometry instead of rebuilding the donor search from scratch for
    every missing coastal cell
  - adds the repaired anomaly to the baseline
  - then dynamically fills missing top layers in the final output
  - writes the native output and can optionally regrid a final delivery copy

- [add_cesm_members_to_glorys_with_coastal_fill.slurm.sh](scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh)
  - CESM to GLORYS orchestration worker for the coastal-fill branch
  - submits one Slurm job per physical variable while processing many CESM
    member anomaly files inside that job
  - delegates the actual per-file anomaly-addition work to
    [add_anomaly_to_baseline_with_coastal_fill.slurm.sh](scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh)

### `scripts/runners/`

Dataset-specific submitters. These define:

- variables
- scenarios
- windows
- input/output paths
- dataset-specific assumptions

and then call the generic workers in `scripts/core/` using `sbatch`.

### `scripts/tools/`

Utility workflows that are still cluster-oriented, but are better understood as
packaging/export/organization steps than as reusable scientific operators.

- [organize_ocean_downscaling_products.sh](scripts/tools/organize_ocean_downscaling_products.sh)
  - builds a curated copy-only product tree under:
    `/home/SB5/ocean_downscaling_products`
  - organizes products into:
    - `baseline/`
    - `future/`
  - supports resolution-aware curated baseline products where available
  - supports both newer `0p25/0p05` future layouts and older CESM-style
    window-folder layouts

- [remap_hindcast_baseline_to_0p05.sh](scripts/tools/remap_hindcast_baseline_to_0p05.sh)
  - reads hindcast baseline climatologies from:
    `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25`
  - writes derived hindcast baseline climatologies to:
    `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05`
  - auto-detects variable directories by requiring a `clim_windows/`
    subdirectory under the hindcast root
  - remaps with `cdo`
  - uses the same grid-type-based method resolution pattern used elsewhere in
    the repository:
    - `remapbil` for regular lon/lat sources
    - `remapdis` for curvilinear or unstructured sources
  - parallelizes at the file level by default

- [split_ocean_downscaling_products_by_depth.sh](scripts/tools/split_ocean_downscaling_products_by_depth.sh)
  - reads curated 3D products from:
    `/home/SB5/ocean_downscaling_products`
  - mirrors them into:
    `/home/SB5/ocean_downscaling_products_bydepth`
  - writes one NetCDF file per depth layer
  - parallelizes at the file level using the allocated Slurm CPUs
  - includes a zero-padded depth token in filenames such as:
    `depth_0005p08m`
  - this remains available for individual-depth slice products, but it is not
    the currently active derived-product workflow

- [aggregate_ocean_downscaling_products_by_depth_bins.sh](scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh)
  - reads curated 3D products from:
    `/home/SB5/ocean_downscaling_products`
  - writes aggregated layer products into one of:
    `/home/SB5/ocean_downscaling_products_layers`
    `/home/SB5/ocean_downscaling_products_pelagic`
  - is designed to run on subtree-specific inputs such as `baseline/<var>` or
    `future/<var>`, while still parallelizing across files inside that subtree
  - supports two bin sets:
    - fine depth intervals such as `0-25 m`, `25-50 m`, `50-100 m`
    - broad pelagic zones such as `epipelagic`, `mesopelagic`,
      `bathypelagic`, `abyssopelagic`
  - computes thickness-weighted vertical means using explicit vertical bounds
    when present, or reconstructed bounds from depth centers when bounds are
    absent
  - writes one NetCDF file per configured depth bin
  - this is the current active derived-product workflow for vertical layer
    products

- [export_ocean_downscaling_products_bydepth_to_csv.sh](scripts/tools/export_ocean_downscaling_products_bydepth_to_csv.sh)
  - reads by-depth NetCDF files from:
    `/home/SB5/ocean_downscaling_products_bydepth`
  - mirrors them into:
    `/home/SB5/ocean_downscaling_products_bydepth_txt`
  - parallelizes at the file level using the allocated Slurm CPUs
  - exports CSV columns as:
    `x,y,depth,<variable>_<units>`
  - this remains available for exporting individual-depth slices, but it is not
    part of the current active derived-product workflow

### `legacy/scripts/slurm/`

Archived pre-refactor workflow scripts kept for provenance and reference.
These are not the active workflow surface anymore, but they remain tracked so
the original production implementations are still documented in the repository.

## Common Processing Stages

The current logic is easiest to understand in three immediate processing layers,
followed by the later downscaling stages.

### 1. Monthly Preparation / Grid Harmonization

This stage creates or prepares monthly files on a common horizontal grid.

Use:

- [temporal_aggregate_regrid.slurm.sh](scripts/core/temporal_aggregate_regrid.slurm.sh)

This stage is the generalized version of what older scripts such as
[glorys_monthly_0p05.slurm.sh](legacy/scripts/slurm/glorys_monthly_0p05.slurm.sh)
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

- [vertical_interpolate_to_reference.slurm.sh](scripts/core/vertical_interpolate_to_reference.slurm.sh)

Typical outputs live in `on_glorys/`.

Examples:

- Hindcast:
  `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/<var>/on_glorys/*.nc`
- IPCC/ESGF:
  `/home/SB5/ipcc_esgf_monthly_1deg/<scenario>/<var>/on_glorys/*.nc`

This stage is the generalized version of the old CESM vertical-matching idea
implemented in
[cesm_vertical_regrid.slurm.sh](legacy/scripts/slurm/cesm_vertical_regrid.slurm.sh).

### 3. Climatology Windows

This stage produces one mean over a requested time window from monthly data.

There are two cases.

#### Many monthly files

Use:

- [climatology_window_from_monthly_files.slurm.sh](scripts/core/climatology_window_from_monthly_files.slurm.sh)

This is the GLORYS-style or hindcast-style case:

- one file per month
- many files in `parts/`
- then merge and compute `timmean`

#### Long monthly time-series files

Use:

- [climatology_window_from_timeseries.slurm.sh](scripts/core/climatology_window_from_timeseries.slurm.sh)

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

- [delta_from_climatologies.slurm.sh](scripts/core/delta_from_climatologies.slurm.sh)
- [add_anomaly_to_baseline.slurm.sh](scripts/core/add_anomaly_to_baseline.slurm.sh)

The original CESM-to-GLORYS production scripts for these later stages are still
kept in [legacy/scripts/slurm](legacy/scripts/slurm),
including:

- [cesm_member_deltas_0p05.slurm.sh](legacy/scripts/slurm/cesm_member_deltas_0p05.slurm.sh)
- [cesm_add_to_glorys_downscale.slurm.sh](legacy/scripts/slurm/cesm_add_to_glorys_downscale.slurm.sh)

So the generalized `core/` plus `runners/` structure should be read as the
full pipeline structure, with the newer generalized code increasingly covering
the later anomaly/delta/downscaling steps as well.

## Current Workflow Families

### GLORYS

Typical older logic:

1. monthly means at `0.05°`
2. baseline climatology from monthly files

Closest modern abstraction:

- monthly prep/harmonization:
  [temporal_aggregate_regrid.slurm.sh](scripts/core/temporal_aggregate_regrid.slurm.sh)
- climatology from monthly files:
  [climatology_window_from_monthly_files.slurm.sh](scripts/core/climatology_window_from_monthly_files.slurm.sh)

Modern GLORYS runners now live in:

- [run_temporal_aggregate_regrid.sh](scripts/runners/glorys/run_temporal_aggregate_regrid.sh)
- [run_climatology_window.sh](scripts/runners/glorys/run_climatology_window.sh)

Current GLORYS logic in the new runner architecture:

1. aggregate daily GLORYS files to monthly means and harmonize them to `0.05°`
2. compute one `2006-2014` baseline climatology per variable from the monthly
   files

Important notes:

- the modern GLORYS runner family is intentionally minimal because this branch
  is a baseline-only workflow in the current repository
- it now follows the same lightweight-runner plus generic-core structure as the
  other dataset families

### CESM

Typical older logic:

1. horizontal regrid
2. vertical interpolation to GLORYS levels
3. climatology windows from member time-series files
4. deltas between future and baseline climatologies
5. addition of deltas to the GLORYS baseline

Closest modern abstraction:

- horizontal regrid:
  [temporal_aggregate_regrid.slurm.sh](scripts/core/temporal_aggregate_regrid.slurm.sh)
- vertical interpolation:
  [vertical_interpolate_to_reference.slurm.sh](scripts/core/vertical_interpolate_to_reference.slurm.sh)
- climatology from time-series files:
  [climatology_window_from_timeseries.slurm.sh](scripts/core/climatology_window_from_timeseries.slurm.sh)
- delta from climatologies:
  [delta_from_climatologies.slurm.sh](scripts/core/delta_from_climatologies.slurm.sh)
- baseline plus anomaly:
  [add_anomaly_to_baseline.slurm.sh](scripts/core/add_anomaly_to_baseline.slurm.sh)
- baseline plus anomaly with coastal fill on the trusted target wet mask:
  [add_anomaly_to_baseline_with_coastal_fill.slurm.sh](scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh)

Modern CESM runners now live in:

- [run_temporal_aggregate_regrid.sh](scripts/runners/cesm_to_glorys/run_temporal_aggregate_regrid.sh)
- [run_vertical_interpolate_to_reference.sh](scripts/runners/cesm_to_glorys/run_vertical_interpolate_to_reference.sh)
- [run_climatology_window.sh](scripts/runners/cesm_to_glorys/run_climatology_window.sh)
- [run_delta_from_climatologies.sh](scripts/runners/cesm_to_glorys/run_delta_from_climatologies.sh)
- [run_add_anomaly_to_baseline.sh](scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline.sh)
- [run_add_anomaly_to_baseline_with_coastal_fill.sh](scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline_with_coastal_fill.sh)

Current CESM logic in the new runner architecture:

1. regrid CESM monthly POP time-series to `1 degree`
2. vertically interpolate them to GLORYS depth levels
3. compute member-specific climatology windows from the regridded and
   vertically matched time series
4. compute member-specific future-minus-baseline deltas
5. add those deltas to the GLORYS baseline for the mapped variables

Important notes:

- the current modern CESM runner family is centered on the `rcp85` branch,
  matching the old downstream CESM workflow organization
- the add-to-baseline stage currently preserves the old variable mapping:
  - `TEMP -> thetao`
  - `SALT -> so`
  - `UVEL -> uo`
- the newer CESM climatology, delta, and addition runners now build explicit
  expected member filenames rather than relying on wildcard first-match logic

### Global Ocean Biogeochemistry Hindcast

Current logic:

1. monthly inputs already organized by `YEAR/MONTH`
2. prepare/harmonize monthly outputs at `0.25 x 0.25`
3. vertically interpolate to GLORYS levels
4. later compute climatology windows

Relevant runners:

- [run_temporal_aggregate_regrid.sh](scripts/runners/global_ocean_biogeochemistry_hindcast/run_temporal_aggregate_regrid.sh)
- [run_vertical_interpolate_to_reference.sh](scripts/runners/global_ocean_biogeochemistry_hindcast/run_vertical_interpolate_to_reference.sh)
- [run_climatology_window.sh](scripts/runners/global_ocean_biogeochemistry_hindcast/run_climatology_window.sh)

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

1. run [run_temporal_aggregate_regrid.sh](scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh)
   - reads `/home/SB5/ipcc_esgf_downloads/<scenario>/<var>/`
   - writes `/home/SB5/ipcc_esgf_monthly_1deg/<scenario>/<var>/parts/`
   - uses `METHOD=auto`
   - auto-selects `remapdis` for curvilinear/unstructured sources and
     `remapbil` for regular lon/lat sources

2. run [run_vertical_interpolate_to_reference.sh](scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh)
   - reads `/parts/`
   - writes `/on_glorys/`

3. run [run_climatology_window.sh](scripts/runners/ipcc_esgf/run_climatology_window.sh)
   - reads `/on_glorys/`
   - writes `/clim_windows/`
   - historical baseline window: `2006-2014`
   - future windows: `2050-2060`, `2090-2100`

4. run [run_delta_from_climatologies.sh](scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh)
   - computes:
     `ssp585 future climatology - historical 2006-2014 climatology`
   - writes `/delta_windows/`
   - also writes `/delta_windows_0p25/` when delta regridding is enabled
   - now targets exact expected climatology filenames instead of picking the
     first wildcard match in the directory

Relevant runners:

- [run_temporal_aggregate_regrid.sh](scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh)
- [run_vertical_interpolate_to_reference.sh](scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh)
- [run_climatology_window.sh](scripts/runners/ipcc_esgf/run_climatology_window.sh)
- [run_delta_from_climatologies.sh](scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh)

### IPCC / ESGF To Hindcast Downscaling

Current logic:

1. use hindcast climatology at `0.25 x 0.25` as the baseline
2. use IPCC/ESGF deltas at `0.25 x 0.25` as the anomaly field
3. add the anomaly field to the baseline
4. if the final product still has missing top layers, fill them from the first
   deeper level with valid values
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

1. run [run_add_anomaly_to_baseline.sh](scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline.sh)
   - reads hindcast baseline climatology files from `clim_windows/`
   - reads IPCC/ESGF delta files from `delta_windows_0p25/`
   - first computes baseline plus anomaly
   - then fills top missing layers dynamically in the final output
   - writes the native downscaled output at `0.25`
   - also writes a `0.05` product using `remapdis`
   - now targets exact expected hindcast baseline and delta filenames instead
     of selecting the first wildcard match

Important note:

- the top-layer fill is now dynamic rather than hard-coded
- it is applied after baseline plus anomaly, on the final downscaled output
- if only the first top layer is missing, only that layer is filled
- if the first several top layers are missing, all missing top layers are
  filled from the first deeper level that contains valid values
- this generalizes the older CESM-to-GLORYS logic, where the top 4 levels were
  always replaced from a fixed deeper layer before addition

Relevant runner:

- [run_add_anomaly_to_baseline.sh](scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline.sh)

#### Coastal-fill variant of the final addition step

The current production downscaling path now uses the coastal-fill final
addition/downscaling worker when the goal is to preserve the trusted target
coastline more faithfully in the final product.

Core worker:

- [add_anomaly_to_baseline_with_coastal_fill.slurm.sh](scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh)

What this worker changes relative to the generic adder:

- it can optionally remap the anomaly to the trusted target baseline grid
  before addition
- it can optionally fill anomaly gaps only within the trusted target wet mask
- it now supports multiple anomaly-fill methods, including
  `distance_weighted`
- it still applies the dynamic top-layer fill after baseline plus anomaly
- it can still optionally regrid the final downscaled output afterward

Methodological note:

- the trusted target can be hindcast, GLORYS, or another current-conditions
  product
- the trusted target baseline file defines the horizontal grid, vertical
  levels, and wet mask used by the coastal-fill logic
- the current implementation relies on that trusted target wet mask to control
  where fill is allowed
- the fill is applied to the anomaly only, never directly to the final
  absolute field
- the current default method is a distance-weighted anomaly fill on the
  trusted target grid, intended to reduce unresolved empty coastal target
  cells more smoothly than a pure nearest-value fill
- the current implementation keeps that same distance-weighted philosophy but
  speeds it up by reusing precomputed local donor geometry on the trusted
  target mask, rather than recomputing donor neighborhoods from scratch for
  each missing anomaly cell
- the code comments also document possible later conservative variants, such as
  only filling cells adjacent to originally valid anomaly cells or reducing the
  effective fill distance

Current coastal-fill controls exposed by the runners:

- `COASTAL_FILL_METHOD`
  - `nearest`
  - `distance_weighted` (current default)
- `COASTAL_FILL_MAX_STEPS`
  - maximum donor search radius in grid-cell steps
- `COASTAL_FILL_WEIGHT_POWER`
  - inverse-distance weighting exponent for the distance-weighted method
- `COASTAL_FILL_MIN_DONORS`
  - target minimum donor count for the distance-weighted method

Runner layout for this coastal-fill branch:

- general configurable runner:
  [run_add_anomaly_to_trusted_baseline_with_coastal_fill.sh](scripts/runners/downscaling/run_add_anomaly_to_trusted_baseline_with_coastal_fill.sh)
- IPCC/ESGF to hindcast wrapper:
  [run_add_anomaly_to_baseline_with_coastal_fill.sh](scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh)
- CESM to GLORYS wrapper:
  [run_add_anomaly_to_baseline_with_coastal_fill.sh](scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline_with_coastal_fill.sh)

Important CESM/GLORYS note:

- the CESM -> GLORYS coastal-fill path now uses a dedicated variable-level
  worker:
  [add_cesm_members_to_glorys_with_coastal_fill.slurm.sh](scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh)
- this restores the legacy CESM -> GLORYS launch behavior:
  one Slurm job per variable, with member anomaly files processed inside that
  job
- this is intentionally different from the hindcast coastal-fill wrapper,
  which submits one job per variable-window combination

Why the runner structure is split this way:

- `scripts/runners/downscaling/` holds the general configurable launcher
- `scripts/runners/ipcc_esgf_to_hindcast/` keeps the current IPCC/ESGF ->
  hindcast production entrypoint
- `scripts/runners/cesm_to_glorys/` keeps the current CESM -> GLORYS
  production entrypoint

This keeps the method generic while leaving the day-to-day launchers in the
source-to-target workflow directories where they are easiest to remember.

## Curated Product Pipeline

After the main scientific workflow produces the final downscaled outputs, the
repository now also supports curated delivery/export trees.

### Curated 3D product tree

Built with:

- [organize_ocean_downscaling_products.sh](scripts/tools/organize_ocean_downscaling_products.sh)
- [run_organize_ocean_downscaling_products.sh](scripts/runners/products/run_organize_ocean_downscaling_products.sh)

Expected output root:

```text
/home/SB5/ocean_downscaling_products/
├── baseline/
│   ├── chl/
│   │   ├── 0p25/
│   │   └── 0p05/
│   ├── o2/
│   │   ├── 0p25/
│   │   └── 0p05/
│   ├── so/
│   │   └── 0p05/
│   ├── thetao/
│   │   └── 0p05/
│   └── uo/
│       └── 0p05/
└── future/
    ├── chl/
    ├── o2/
    ├── so/
    ├── thetao/
    └── uo/
```

Notes:

- `baseline/` stores curated climatological reference products
- baseline products are now organized by resolution when available
- `chl` and `o2` can include both `0p25` and derived `0p05` hindcast baseline
  products
- `thetao`, `so`, and `uo` currently contribute `0p05` baseline products from
  the GLORYS reference branch
- `future/` stores curated future/downscaled products
- the runner now submits one Slurm job per curated subtree:
  - `baseline/<var>`
  - `future/<var>/<window>` for windowed future branches
- within each submitted job, the tool can copy multiple NetCDF files in
  parallel using the allocated CPUs
- `chl` and `o2` future branches preserve both `0p25` and `0p05` products
  under each future window when that layout exists
- the tool copies files; it does not move or delete the original workflow trees

### Derived hindcast baseline 0.05 tree

Built with:

- [remap_hindcast_baseline_to_0p05.sh](scripts/tools/remap_hindcast_baseline_to_0p05.sh)
- [run_remap_hindcast_baseline_to_0p05.sh](scripts/runners/products/run_remap_hindcast_baseline_to_0p05.sh)

Expected output root:

```text
/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05/
└── <var>/
    └── clim_windows/
```

Notes:

- derives `0.05 x 0.05` hindcast baseline climatologies from the existing
  hindcast `0.25 x 0.25` climatology tree
- keeps the same variable-folder and `clim_windows/` structure under a new
  top-level root
- the runner submits one Slurm job per variable directory
- variable directories are auto-detected by requiring `clim_windows/`, so
  temporary folders such as `tmp/` are excluded
- output filenames add the suffix `_grid_0p05_global.nc`
- uses `cdo` remapping
- uses the repository-standard grid-type detection logic:
  - `remapbil` for regular lon/lat sources
  - `remapdis` for curvilinear/unstructured sources
- parallelizes at the file level by default, using the allocated Slurm CPUs

### Curated depth-layer NetCDF tree

Built with:

- [aggregate_ocean_downscaling_products_by_depth_bins.sh](scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh)
- [run_aggregate_ocean_downscaling_products_fine_layers.sh](scripts/runners/products/run_aggregate_ocean_downscaling_products_fine_layers.sh)

Expected output root:

```text
/home/SB5/ocean_downscaling_products_layers/
├── baseline/
└── future/
```

Notes:

- mirrors the curated `baseline/future` structure
- each 3D NetCDF file becomes one NetCDF file per fine depth interval
- the runner submits one job per main subtree:
  - `baseline/<var>`
  - `future/<var>`
- within each submitted job, the tool still parallelizes over files
- current intervals are left-closed and right-open:
  - `[0,25)`
  - `[25,50)`
  - `[50,100)`
  - `[100,200)`
  - `[200,400)`
  - `[400,600)`
  - `[600,800)`
  - `[800,1000)`
  - `[1000,1500)`
  - `[1500,2000)`
  - `[2000,3000)`
  - `[3000,4000)`
  - `[4000,5000)`
  - `[5000,6000)`
- if a bin contains multiple levels, the tool computes a thickness-weighted
  vertical mean
- if a bin contains one level, that level is emitted directly using the
  layer-range filename
- vertical weights come from explicit bounds when present, or reconstructed
  bounds derived from the depth-center coordinate when bounds are absent
- the tool adds output metadata including:
  - `depth_bin_label`
  - `depth_bin_lower_m`
  - `depth_bin_upper_m`
  - `depth_bin_mode`
  - `vertical_aggregation_method`
  - `vertical_bounds_source`
- the current tool uses file-level parallelism and is configured to use `6`
  CPUs per Slurm task
- output filenames follow patterns such as:
  - `global_ocean_biogeochemistry_hindcast_chl_clim_2006-2014_layer_0000_0025m.nc`
  - `ipcc_esgf_to_hindcast_chl_downscaled_2050-2060_layer_1000_1500m.nc`

Method note:

- this workflow assumes that products on the shared GLORYS-like depth grid can
  be thickness-weighted using either explicit vertical bounds or, when those
  bounds are absent, bounds reconstructed from the depth-center coordinate
- that assumption applies broadly to any product using this common vertical
  grid in the repository, not only to the downscaled products
- for the current example files tracked in `legacy/`, explicit vertical bounds
  were not present, so reconstructed bounds are the expected default behavior

### Curated pelagic-zone NetCDF tree

Built with:

- [aggregate_ocean_downscaling_products_by_depth_bins.sh](scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh)
- [run_aggregate_ocean_downscaling_products_pelagic_layers.sh](scripts/runners/products/run_aggregate_ocean_downscaling_products_pelagic_layers.sh)

Expected output root:

```text
/home/SB5/ocean_downscaling_products_pelagic/
├── baseline/
└── future/
```

Notes:

- mirrors the curated `baseline/future` structure
- each 3D NetCDF file becomes one NetCDF file per pelagic zone
- the runner submits one job per main subtree:
  - `baseline/<var>`
  - `future/<var>`
- within each submitted job, the tool still parallelizes over files
- current zones are:
  - `epipelagic` for `[0,200)`
  - `mesopelagic` for `[200,1000)`
  - `bathypelagic` for `[1000,4000)`
  - `abyssopelagic` for `[4000,6000)`
- the same weighting and single-level fallback rules used for fine layers also
  apply here
- the current tool uses file-level parallelism and is configured to use `6`
  CPUs per Slurm task
- output filenames follow patterns such as:
  - `global_ocean_biogeochemistry_hindcast_chl_clim_2006-2014_zone_epipelagic_0000_0200m.nc`
  - `b.e11.BRCP85C5CNBDRD.f09_g16.001.pop.h.TEMP.200601-210012.1deg_on_glorys_downscaled_thetao_2050-2060_zone_bathypelagic_1000_4000m.nc`

Method note:

- the same vertical-weighting assumption used for fine depth layers applies
  here as well
- pelagic-zone means therefore depend on either explicit vertical bounds or
  reconstructed bounds from the shared depth-center coordinate

### Curated by-depth NetCDF tree

Built with:

- [split_ocean_downscaling_products_by_depth.sh](scripts/tools/split_ocean_downscaling_products_by_depth.sh)
- [run_split_ocean_downscaling_products_by_depth.sh](scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh)

Expected output root:

```text
/home/SB5/ocean_downscaling_products_bydepth/
├── baseline/
└── future/
```

Notes:

- mirrors the curated `baseline/future` structure
- each 3D NetCDF file becomes one 2D NetCDF file per depth layer
- the current tool uses file-level parallelism and is configured to use `6`
  CPUs per Slurm task
- depth is encoded in the filename with a zero-padded safe token such as:
  - `depth_0000p49m`
  - `depth_0005p08m`
  - `depth_0453p94m`
  - `depth_5727p92m`
- this workflow remains available for producing individual-depth slices, but it
  is not the current active derived-product path

### Curated by-depth CSV tree

Built with:

- [export_ocean_downscaling_products_bydepth_to_csv.sh](scripts/tools/export_ocean_downscaling_products_bydepth_to_csv.sh)
- [run_export_ocean_downscaling_products_bydepth_to_csv.sh](scripts/runners/products/run_export_ocean_downscaling_products_bydepth_to_csv.sh)

Expected output root:

```text
/home/SB5/ocean_downscaling_products_bydepth_txt/
├── baseline/
└── future/
```

Notes:

- mirrors the by-depth NetCDF tree
- exports each by-depth NetCDF file to one CSV
- the current tool uses file-level parallelism and is configured to use `6`
  CPUs per Slurm task
- CSV columns are:
  - `x`
  - `y`
  - `depth`
  - `<variable>_<units>`
- singleton dimensions such as `time=1` are squeezed before export
- this workflow remains available for downstream tabular export of
  individual-depth slices, but it is not the current active derived-product
  path

## Download And Utility Scripts

Located in [scripts/bash](scripts/bash):

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

## Methodological Assumptions

The current downscaling workflow makes several explicit methodological
assumptions that should be kept in mind when interpreting the outputs.

- Future change is represented as a climatological anomaly or delta:
  `future climatology - historical climatology`

- The final downscaled future field is constructed as:
  `baseline climatology + anomaly/delta`

- The hindcast climatology is treated as the historical baseline for the
  IPCC-to-hindcast downscaling branch.

- Vertical matching to the GLORYS reference grid is performed before the
  climatology and delta steps for branches where comparable vertical structure
  is required.

- In the coastal-fill variant of the final addition step, missing anomaly cells
  may be filled only within the trusted target wet mask defined by the target
  baseline/current-conditions product. That means the trusted target product
  controls the horizontal grid, vertical levels, and ocean-mask geometry used
  by the fill logic.

- The current default coastal-fill method is distance-weighted anomaly repair
  on that trusted target geometry. The anomaly, not the final absolute field,
  is what gets reconstructed before the addition step.

- The current faster implementation keeps that same method but reuses
  precomputed local donor geometry on the trusted target mask so repeated
  coastal-cell donor searches do not have to be rebuilt from scratch for every
  file.

- The current coastal-fill implementation is intentionally target-mask-based,
  not coastline-shape-aware beyond that mask. It is meant as an anomaly-repair
  step on the trusted target geometry, not as a guarantee of fully conservative
  coastal behavior in every application.

- Horizontal remapping method is not assumed to be universal across all model
  products:
  curvilinear or unstructured native grids may require `remapdis`, while
  regular lon/lat grids may still be handled with `remapbil`.

- Regridding choices are treated as workflow assumptions, not purely technical
  details, because they can introduce or remove visible artifacts such as seams.

- Missing top layers are handled pragmatically in the final downscaled product:
  after baseline plus anomaly is computed, any missing top layer or layers are
  filled from the first deeper level that contains valid values in that same
  output column.

- Baseline climatologies built from monthly files can also apply the same
  top-gap fill logic after climatology generation. This allows baseline
  products such as hindcast biogeochemistry climatologies to stabilize missing
  shallow layers without changing the upstream monthly/intermediate files.

- The top-layer fill is intended to stabilize shallow output structure where the
  source products do not provide complete surface information. It is therefore a
  methodological choice, not just a file-repair step.

- Mask consistency across baseline, climatology, delta, and downscaled products
  matters. Older or stale files with outdated naming conventions can produce
  misleading results if later runners pick them up by wildcard.

- This workflow is a statistical downscaling approach built from climatologies,
  anomalies, interpolation, and remapping. It is not a dynamical ocean-model
  simulation.

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

- `add_anomaly_to_baseline.slurm.sh` and
  `add_anomaly_to_baseline_with_coastal_fill.slurm.sh` are the final
  addition/downscaling workers.
  They combine a baseline climatology with an anomaly/delta field, with the
  coastal-fill variant first repairing missing anomaly cells on the trusted
  target wet mask before addition.

- The downscaling part of the overall workflow still continues after
  climatologies. Climatologies are not the final product; they are the inputs to
  later anomaly, delta, and downscaling stages.
