<table>
  <tr>
    <td valign="top">
      <h1>Ocean Downscaling And Delivery Pipeline</h1>
  </td>
    <td valign="top" align="right">
      <img src="docs/assets/save-the-blue-five-logo.png" alt="Save The Blue Five logo" width="260">
    </td>
  </tr>
</table>

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
   - export parquet, GeoTIFF, or CSV outputs

If you only need the current logic, focus first on:

- [Architecture And Script Roles](#architecture-and-script-roles)
- [Common Processing Stages](#common-processing-stages)
- [Current Workflow Families](#current-workflow-families)
- [Curated Product Pipeline](#curated-product-pipeline)

## Current End-To-End Workflow Map

At the highest level, the repository has two kinds of workflows:

1. **Scientific production workflows**
   - build trusted present-day baseline climatologies
   - build model-specific climatological change fields
   - add those change fields to the trusted baseline
   - write final downscaled NetCDF products

2. **Curated delivery workflows**
   - reorganize final NetCDF outputs into delivery trees
   - aggregate depth-layer or pelagic products
   - export delivery-ready parquet, GeoTIFF, or CSV products

The current scientific branches are:

- `glorys/`
  - prepares the GLORYS baseline products
- `global_ocean_biogeochemistry_hindcast/`
  - prepares the hindcast baseline products
- `ipcc_esgf/`
  - prepares IPCC/ESGF monthly products, climatologies, and change fields
- `ipcc_esgf_to_hindcast/`
  - adds IPCC/ESGF change fields to the configured trusted baseline
    (`GLORYS` for physics/sea-ice and hindcast for BGC)
- `cesm_to_glorys/`
  - adds CESM member change fields to the GLORYS baseline

The current CMIP6/IPCC expansion targets five first-member model branches:
`CNRM-ESM2-1`, `IPSL-CM6A-LR`, `MPI-ESM1-2-HR`, `MPI-ESM1-2-LR`, and
`UKESM1-0-LL`. It covers `historical`, `ssp126`, `ssp245`, and `ssp585`,
with a `2006-2014` historical baseline and future windows `2030-2060`,
`2050-2060`, and `2090-2100`. The 3D stack is `thetao`, `so`, `ph`, `o2`,
`chl`, `uo`, `vo`, and `zooc`; 2D diagnostic or sea-ice layers are `zos`,
`mlotst`, and `siconc`. The anomaly-add target is split by trusted baseline:
`thetao`, `so`, `uo`, `vo`, `zos`, `mlotst`, and `siconc` use GLORYS;
`chl`, `o2`, and `ph` use the GLORYS-coast hindcast; `zooc` stops at delta
until a trusted present-day baseline is defined.

Current anomaly-add and baseline matrix:

| Variable(s) | Source class | Model processing | Delta regrid | Trusted baseline for add | Native add grid | Coastal/wet-mask rule |
| --- | --- | --- | --- | --- | --- | --- |
| `thetao`, `so`, `uo`, `vo` | 3D ocean | vertical interpolation to GLORYS levels, climatology, delta | `0p05` GLORYS grid | GLORYS12v1 | `0p05` GLORYS | baseline finite mask |
| `chl`, `o2`, `ph` | 3D BGC | vertical interpolation to GLORYS levels, climatology, delta | `0p25` hindcast anomaly grid | Global Ocean Biogeochemistry Hindcast, remapped to GLORYS coast | `0p05` GLORYS coast | GLORYS `thetao` wet mask for coastal fill |
| `zos`, `mlotst` | 2D ocean | climatology, delta | `0p05` GLORYS grid | GLORYS12v1 | `0p05` GLORYS | baseline finite mask |
| `siconc` | 2D sea ice | climatology, delta | `0p05` GLORYS grid | GLORYS12v1 | `0p05` GLORYS | baseline finite mask |
| `zooc` | 3D BGC CMIP6 variable | vertical interpolation to GLORYS levels, climatology, delta | none | none configured | stop at delta | add later when a trusted baseline is selected |

The future products use an additive change-field, or delta-change, approach:
a model-specific change field is first calculated from the difference between
that model's future-period climatology and its historical/current reference
climatology. That change field is then added to a trusted present-day target
baseline, following the IPCC Data Distribution Centre description of
[constructing change fields](https://www.ipcc-data.org/guidelines/pages/change_field.html):

```text
change field = model future climatology - model historical/current climatology
downscaled future = trusted target baseline + change field
```

The current curated-product chain is:

1. [run_organize_ocean_downscaling_products.sh](scripts/runners/products/run_organize_ocean_downscaling_products.sh)
2. [run_aggregate_ocean_downscaling_products_fine_layers.sh](scripts/runners/products/run_aggregate_ocean_downscaling_products_fine_layers.sh)
3. [run_aggregate_ocean_downscaling_products_pelagic_layers.sh](scripts/runners/products/run_aggregate_ocean_downscaling_products_pelagic_layers.sh)
4. [run_export_ocean_downscaling_products_layers_to_parquet.sh](scripts/runners/products/run_export_ocean_downscaling_products_layers_to_parquet.sh)
5. [run_export_ocean_downscaling_products_pelagic_to_parquet.sh](scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_parquet.sh)
6. [run_export_ocean_downscaling_products_layers_to_geotiff.sh](scripts/runners/products/run_export_ocean_downscaling_products_layers_to_geotiff.sh)
7. [run_export_ocean_downscaling_products_pelagic_to_geotiff.sh](scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_geotiff.sh)
8. [run_stage_ocean_downscaling_sample_products.sh](scripts/runners/products/run_stage_ocean_downscaling_sample_products.sh)

Optional individual-depth products can also be derived from the same curated
3D tree with [run_split_ocean_downscaling_products_by_depth.sh](scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh).
Set `MAX_DEPTH_M=600` and `GEOTIFF=yes` to create shallow individual-depth
NetCDF and GeoTIFF products for species workflows.
The resulting depth NetCDF tree can be exported to Parquet with
[run_export_ocean_downscaling_products_depths_to_parquet.sh](scripts/runners/products/run_export_ocean_downscaling_products_depths_to_parquet.sh).

## Purpose

At a high level, the repository now supports three reusable processing stages:

1. monthly preparation and horizontal harmonization
2. vertical interpolation to a GLORYS reference grid
3. climatology windows from either monthly files or long time-series files

These stages sit inside a broader downscaling pipeline. After climatologies are
computed, later steps can still include:

4. model-specific change fields between reference and future climatology windows
5. addition of change fields to a trusted present-day baseline
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
│   ├── lib/                        # Shared runner helpers
│   │   └── ipcc_esgf_discovery.sh
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
│   │   │   ├── run_remap_hindcast_baseline_to_0p05_glorys_coast.sh
│   │   │   ├── run_aggregate_ocean_downscaling_products_fine_layers.sh
│   │   │   ├── run_aggregate_ocean_downscaling_products_pelagic_layers.sh
│   │   │   ├── run_split_ocean_downscaling_products_by_depth.sh
│   │   │   ├── run_export_ocean_downscaling_products_bydepth_to_csv.sh
│   │   │   ├── run_export_ocean_downscaling_products_layers_to_parquet.sh
│   │   │   ├── run_export_ocean_downscaling_products_pelagic_to_parquet.sh
│   │   │   ├── run_export_ocean_downscaling_products_depths_to_parquet.sh
│   │   │   ├── run_export_ocean_downscaling_products_layers_to_geotiff.sh
│   │   │   └── run_export_ocean_downscaling_products_pelagic_to_geotiff.sh
│   │   ├── glorys/
│   │   │   ├── run_temporal_aggregate_regrid.sh
│   │   │   └── run_climatology_window.sh
│   │   └── other_model/
│   ├── tools/                      # Packaging/export/organization utilities
│   │   ├── organize_ocean_downscaling_products.sh
│   │   ├── remap_hindcast_baseline_to_0p05.sh
│   │   ├── remap_hindcast_baseline_to_0p05_glorys_coast.sh
│   │   ├── aggregate_ocean_downscaling_products_by_depth_bins.sh
│   │   ├── split_ocean_downscaling_products_by_depth.sh
│   │   ├── export_ocean_downscaling_products_bydepth_to_csv.sh
│   │   ├── export_ocean_downscaling_products_to_parquet.sh
│   │   └── export_ocean_downscaling_products_to_geotiff.sh
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
  - can repair missing anomaly cells only inside the trusted target wet mask or
    an external coastal mask such as the GLORYS `thetao` wet mask
  - can optionally fill missing baseline cells inside an external coastal mask
    before addition, but the current IPCC/ESGF biogeochemistry path now reads
    an already-filled GLORYS-coast hindcast baseline and leaves this option off
  - currently supports `nearest` and `distance_weighted` anomaly fill methods
  - the current distance-weighted implementation reuses precomputed local
    donor geometry instead of rebuilding the donor search from scratch for
    every missing coastal cell
  - donor values come only from the original finite field being repaired, so
    newly filled coastal cells do not become donors during the same fill pass
  - can optionally require complete anomaly coverage inside the wet mask after
    the bounded donor search; this second pass lets repaired anomaly cells
    propagate locally to fill any remaining wet-mask gaps
  - when complete coverage is required, any anomaly cells still missing after
    local propagation can receive an explicit fallback anomaly value; the
    current IPCC/ESGF biogeochemistry default is `0`, meaning baseline
    unchanged where no anomaly donor exists
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
  - reads the current final downscaled layout:
    `/home/SB5/downscaled/<model>/<realization>/<scenario>/<var>/...`
  - writes future products with that provenance preserved:
    `future/<model>/<realization>/<scenario>/<var>/<window>/<resolution>/`
  - still supports older CESM-style window-folder layouts as a transition
    fallback

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

- [remap_hindcast_baseline_to_0p05_glorys_coast.sh](scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh)
  - current preferred biogeochemistry baseline derivation for downscaling
  - reads hindcast baseline climatologies from:
    `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25`
  - remaps each variable to the GLORYS `0.05` grid
  - fills missing coastal cells inside the GLORYS wet mask, currently taken
    from the GLORYS `thetao` `2006-2014` climatology
  - writes a complete all-variable root:
    `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast`
  - keeps the same `<var>/clim_windows/` tree and
    `_grid_0p05_global.nc` filename suffix
  - uses only originally finite cells as donors during coastal interpolation;
    newly filled cells do not become donors during the same pass
  - rewrites outputs as NetCDF4 with zlib compression, so old/new file sizes
    are not a reliable coverage check; compare valid/missing cell counts
    instead

- [split_ocean_downscaling_products_by_depth.sh](scripts/tools/split_ocean_downscaling_products_by_depth.sh)
  - reads curated 3D products from:
    `/home/SB5/ocean_downscaling_products`
  - mirrors them into one of:
    `/home/SB5/ocean_downscaling_products_bydepth`
    `/home/SB5/ocean_downscaling_products_depths`
  - writes one NetCDF file per depth layer
  - supports `MAX_DEPTH_M` to limit exported depth centers, for example
    `MAX_DEPTH_M=600`
  - parallelizes at the file level using the allocated Slurm CPUs
  - includes a zero-padded depth token in filenames such as:
    `depth_0005p079m`
  - depth tokens use `MIN_DECIMALS=3` by default; if two source depths round to
    the same token, the splitter stops with an error instead of overwriting
    output files
  - the runner can also submit a dependent GeoTIFF export job with
    `GEOTIFF=yes`, reusing
    [export_ocean_downscaling_products_to_geotiff.sh](scripts/tools/export_ocean_downscaling_products_to_geotiff.sh)

- [aggregate_ocean_downscaling_products_by_depth_bins.sh](scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh)
  - reads curated 3D products from:
    `/home/SB5/ocean_downscaling_products`
  - writes aggregated layer products into one of:
    `/home/SB5/ocean_downscaling_products_layers`
    `/home/SB5/ocean_downscaling_products_pelagic`
  - is designed to run on subtree-specific inputs such as `baseline/<var>` or
    `future/<model>/<realization>/<scenario>/<var>`, while still
    parallelizing across files inside that subtree
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

- [export_ocean_downscaling_products_to_geotiff.sh](scripts/tools/export_ocean_downscaling_products_to_geotiff.sh)
  - reads 2D NetCDF products from trees such as:
    `/home/SB5/ocean_downscaling_products_layers`
    `/home/SB5/ocean_downscaling_products_pelagic`
    `/home/SB5/ocean_downscaling_products_depths`
  - mirrors them into compressed GeoTIFF trees such as:
    `/home/SB5/ocean_downscaling_products_layers_geotiff`
    `/home/SB5/ocean_downscaling_products_pelagic_geotiff`
    `/home/SB5/ocean_downscaling_products_depths_geotiff`
  - encodes floating-point values as integers:
    `stored_value = round(real_value * scale_factor)`
  - stores the corresponding decode rule as:
    `real_value = stored_value / scale_factor`
  - uses variable-aware scale defaults and automatically promotes from
    `Int16` to `Int32` when encoded values do not fit safely in `Int16`
  - writes `geotiff_manifest.csv` with scale factors, data types, nodata
    values, units, and source/output paths for downstream Shiny/terra use
  - this is a complementary final delivery export beside the current Parquet
    products

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
  `/home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<scenario>/<var>/parts/*.nc`

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
- IPCC/ESGF 3D variables:
  `/home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<scenario>/<var>/on_glorys/*.nc`

2D IPCC/ESGF variables such as `zos`, `mlotst`, and `siconc` skip this stage
and use the horizontally harmonized `parts/` files directly for climatology
windows.

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

- model-specific climatological change fields
- remapping of change-field products where needed
- addition of change fields to a baseline field
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
- baseline plus anomaly with coastal fill on a target wet mask, currently the
  GLORYS wet mask for IPCC/ESGF biogeochemistry:
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
4. compute member-specific CESM change fields from future and `2006-2014`
   climatologies
5. add those CESM change fields to the GLORYS baseline for the mapped variables

Important notes:

- the current modern CESM runner family is centered on the `rcp85` branch,
  matching the old downstream CESM workflow organization
- the add-to-baseline stage currently preserves the old variable mapping:
  - `TEMP -> thetao`
  - `SALT -> so`
  - `UVEL -> uo`
- final CESM downscaled products now use the same provenance order as the
  IPCC/ESGF branch:
  `/home/SB5/downscaled/cesm_f09_g16/<member>/rcp85/<var>/0p05/<window>/`
  where `<member>` is derived from the CESM filename, for example `001`
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

1. discover ESGF/IPCC files and write reviewable manifests
2. fetch/download selected first-member files
3. discover model, scenario, member, variable, table, and grid from CMIP-style
   filenames
4. regrid monthly time-series on native `gn` grids to `1 x 1`
5. vertically interpolate only 3D variables to GLORYS levels
6. compute climatology windows from vertically matched 3D products or from
   horizontally harmonized 2D products
7. compute IPCC/ESGF change fields from future and historical
   climatologies
8. regrid those change fields by trusted-baseline family:
   - GLORYS-target variables to `0.05 x 0.05`
   - hindcast-target variables to `0.25 x 0.25`
   - variables without a trusted baseline stay at `/delta_windows/`

Expected input organization:

```text
/home/SB5/ipcc_esgf/downloads/
└── <model>/
    └── <member>/
        └── <scenario>/
            └── <var>/
                └── *.nc
```

Regridded monthly products are organized as:

```text
/home/SB5/ipcc_esgf/monthly_1deg/
└── <model>/
    └── <member>/
        ├── historical/
        │   └── <var>/
        │       ├── parts/
        │       ├── on_glorys/        # 3D variables only
        │       ├── clim_windows/
        │       ├── tmp_clim/
        │       └── tmp_vinterp/      # 3D variables only
        └── <ssp-scenario>/
            └── <var>/
                ├── parts/
                ├── on_glorys/        # 3D variables only
                ├── clim_windows/
                ├── delta_windows/
                ├── delta_windows_0p05/   # GLORYS-target variables only
                ├── delta_windows_0p25/   # hindcast-target variables only
                ├── tmp_clim/
                ├── tmp_delta/
                └── tmp_vinterp/      # 3D variables only
```

Example:

```text
/home/SB5/ipcc_esgf/monthly_1deg/CNRM-ESM2-1/r1i1p1f2/ssp585/chl/delta_windows_0p25/
/home/SB5/ipcc_esgf/monthly_1deg/CNRM-ESM2-1/r1i1p1f2/ssp585/thetao/delta_windows_0p05/
```

The helper [ipcc_esgf_discovery.sh](scripts/lib/ipcc_esgf_discovery.sh)
is sourced internally by the runners. It parses names such as:

```text
chl_Omon_CNRM-ESM2-1_ssp585_r1i1p1f2_gn_201501-210012.nc
```

and carries `model`, `scenario`, and `member` into later filenames. The default
member behavior is `MEMBER=auto`: one member is used automatically, zero members
are skipped with a warning, and multiple members stop the run until
`MEMBER=<member>` is set explicitly.

Before downloading large NetCDF files, use
[discover_ipcc_esgf_nci_cmip6.R](scripts/R/discover_ipcc_esgf_nci_cmip6.R)
to query the ESGF NCI search API and write reviewable manifests:

```bash
Rscript scripts/R/discover_ipcc_esgf_nci_cmip6.R
```

The current CMIP6/IPCC search target is:

- models:
  `CNRM-ESM2-1`, `IPSL-CM6A-LR`, `MPI-ESM1-2-HR`, `MPI-ESM1-2-LR`,
  and `UKESM1-0-LL`
- experiments:
  `historical`, `ssp126`, `ssp245`, and `ssp585`
- member:
  first available realization/member for each model, variable, and experiment
- ocean table/grid:
  `Omon` / `gn`
- sea-ice table/grid:
  `SImon` / `gn` for `siconc`
- historical window:
  `2006-2014`
- future windows:
  `2030-2060`, `2050-2060`, and `2090-2100`

Variables are split by processing dimension:

- 3D ocean stack:
  `thetao`, `so`, `ph`, `o2`, `chl`, `uo`, `vo`, and `zooc`
- 2D diagnostic or sea-ice layers:
  `zos`, `mlotst`, and `siconc`

`siconc` now has a GLORYS present-day baseline path. `zooc` is still a
future/delta-side variable until a trusted current-condition baseline is
defined.

To test or restrict the scan to candidate models:

```bash
SOURCE_IDS="CNRM-ESM2-1 IPSL-CM6A-LR" \
VARS="thetao so o2 chl siconc" \
Rscript scripts/R/discover_ipcc_esgf_nci_cmip6.R
```

Outputs are written under `data/manifests/`, including selected first-member
file URLs and model-level coverage summaries.

The R fetch helper is dry-run by default:

```bash
MANIFEST=data/manifests/ipcc_esgf_nci_cmip6_ocean_plus_siconc_wget_manifest.csv \
MODELS="CNRM-ESM2-1 IPSL-CM6A-LR MPI-ESM1-2-HR MPI-ESM1-2-LR UKESM1-0-LL" \
Rscript scripts/R/fetch_ipcc_esgf_cmip6_manifest.R
```

To perform real downloads, add `DOWNLOAD=yes`. The target root remains
`/home/SB5/ipcc_esgf/downloads`.

Operational sequence for the current IPCC branch:

1. run [run_temporal_aggregate_regrid.sh](scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh)
   - reads `/home/SB5/ipcc_esgf/downloads/<model>/<member>/<scenario>/<var>/`
   - writes `/home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<scenario>/<var>/parts/`
   - uses `METHOD=auto`
   - auto-selects `remapdis` for curvilinear/unstructured sources and
     `remapbil` for regular lon/lat sources

2. run [run_vertical_interpolate_to_reference.sh](scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh)
   - reads `/parts/`
   - writes `/on_glorys/`
   - processes only 3D variables:
     `thetao`, `so`, `ph`, `o2`, `chl`, `uo`, `vo`, and `zooc`
   - 2D variables skip this stage

3. run [run_climatology_window.sh](scripts/runners/ipcc_esgf/run_climatology_window.sh)
   - reads `/on_glorys/` for 3D variables
   - reads `/parts/` for 2D variables
   - writes `/clim_windows/`
   - historical baseline window: `2006-2014`
   - future windows: `2030-2060`, `2050-2060`, and `2090-2100`

4. run [run_delta_from_climatologies.sh](scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh)
   - computes a change field from each discovered future climatology relative
     to historical `2006-2014` climatology
   - writes `/delta_windows/`
   - writes `/delta_windows_0p05/` for GLORYS-target variables:
     `thetao`, `so`, `uo`, `vo`, `zos`, `mlotst`, and `siconc`
   - writes `/delta_windows_0p25/` for hindcast-target variables:
     `chl`, `o2`, and `ph`
   - leaves variables without a trusted baseline, currently `zooc`, at
     `/delta_windows/`
   - uses `log_ratio` deltas for `chl`; other variables use additive deltas
   - now targets exact expected climatology filenames instead of picking the
     first wildcard match in the directory

Relevant runners:

- [run_temporal_aggregate_regrid.sh](scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh)
- [run_vertical_interpolate_to_reference.sh](scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh)
- [run_climatology_window.sh](scripts/runners/ipcc_esgf/run_climatology_window.sh)
- [run_delta_from_climatologies.sh](scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh)

### IPCC / ESGF To Trusted Baselines

Current logic:

The IPCC/ESGF final add wrapper routes variables by trusted baseline family.

GLORYS-target variables follow the CESM-to-GLORYS anomaly/add logic:

1. use GLORYS12v1 `0.05 x 0.05` climatology as the trusted baseline
2. use IPCC/ESGF change fields already regridded to the GLORYS `0.05 x 0.05`
   grid
3. add the change field directly to the GLORYS baseline without another anomaly
   remap
4. fill anomaly coastal gaps inside the GLORYS baseline finite mask
5. write only the native downscaled output at `0.05 x 0.05`

Hindcast-target variables use the GLORYS-coast-filled BGC hindcast branch:

1. use the GLORYS-coast-filled hindcast biogeochemistry climatology at
   `0.05 x 0.05` as the trusted baseline
2. use IPCC/ESGF change fields regridded to the hindcast `0.25 x 0.25`
   anomaly grid
3. remap those change fields to the trusted hindcast baseline grid
4. fill missing anomaly cells inside the GLORYS wet mask plus any cells that
   are already valid in the fixed hindcast baseline
   - for current IPCC/ESGF biogeochemistry, remaining missing anomaly cells
     inside that allowed domain are forced complete with a local propagation
     fallback
5. add the repaired anomaly to the already GLORYS-coast-filled hindcast
   baseline
6. if the final product still has missing top layers, fill them from the first
   deeper level with valid values
7. write the native downscaled output at `0.05 x 0.05`
8. also regrid the downscaled product to `0.25 x 0.25`

Expected inputs:

- GLORYS baseline climatologies:
  `/home/SB5/reanalysis/glorys12v1/monthly_0p05/<var>/clim_windows/*.nc`
- GLORYS-target IPCC/ESGF change-field files already regridded to
  `0.05 x 0.05`:
  `/home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<scenario>/<var>/delta_windows_0p05/*.nc`
- GLORYS-coast-filled hindcast baseline climatologies:
  `/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast/<var>/clim_windows/*.nc`
- hindcast-target IPCC/ESGF change-field files already regridded to
  `0.25 x 0.25`:
  `/home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<scenario>/<var>/delta_windows_0p25/*.nc`

Downscaled outputs are organized as:

```text
/home/SB5/downscaled/
└── <model>/
    └── <realization>/
        └── <scenario>/
            └── <var>/
                ├── 0p25/
                │   ├── 2030-2060/
                │   ├── 2050-2060/
                │   └── 2090-2100/
                └── 0p05/
                    ├── 2030-2060/
                    ├── 2050-2060/
                    └── 2090-2100/
```

Example:

```text
/home/SB5/downscaled/CNRM-ESM2-1/r1i1p1f2/ssp585/chl/0p05/2050-2060/
```

Operational sequence for this final stage:

1. run [run_add_anomaly_to_baseline_with_coastal_fill.sh](scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh)
   - reads GLORYS baseline climatology files from
     `/home/SB5/reanalysis/glorys12v1/monthly_0p05` for
     `thetao`, `so`, `uo`, `vo`, `zos`, `mlotst`, and `siconc`
   - reads GLORYS-coast hindcast baseline climatology files from
     `/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast`
     for `chl`, `o2`, and `ph`
   - reads GLORYS-target IPCC/ESGF delta files from member-aware
     `delta_windows_0p05/` trees under `/home/SB5/ipcc_esgf/monthly_1deg`
   - reads hindcast-target IPCC/ESGF delta files from member-aware
     `delta_windows_0p25/` trees under `/home/SB5/ipcc_esgf/monthly_1deg`
   - leaves variables without a configured trusted baseline, currently `zooc`,
     at the delta stage
   - writes to `/home/SB5/downscaled/<model>/<realization>/<scenario>/<var>/`
   - for GLORYS-target variables, adds `0.05` anomalies directly to GLORYS
     `0.05` baselines
   - for hindcast-target variables, remaps the anomaly to the GLORYS-coast
     hindcast `0.05` grid
   - fills anomaly coastal gaps inside the target baseline wet mask; hindcast
     BGC variables use the GLORYS `thetao` mask for GLORYS-coast filling
   - computes fixed baseline plus fixed anomaly
   - then fills top missing layers dynamically in the final output
   - writes the native downscaled output at `0.05`
   - also writes a `0.25` product using `remapdis` only for hindcast-target
     variables
   - now targets exact expected baseline and delta filenames instead
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

- [run_add_anomaly_to_baseline_with_coastal_fill.sh](scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh)

The older non-coastal IPCC/ESGF runner is preserved under
`legacy/deprecated/` for reference only.

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
  or an external mask such as the GLORYS `thetao` wet mask
- it can optionally fill baseline gaps before addition, but this is now off by
  default for IPCC/ESGF biogeochemistry because the baseline root is already
  `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast`
- it now supports multiple anomaly-fill methods, including
  `distance_weighted`
- it can optionally require complete anomaly coverage inside the allowed wet
  mask with `COASTAL_FILL_REQUIRE_COMPLETE=yes`
- it still applies the dynamic top-layer fill after baseline plus anomaly
- it can still optionally regrid the final downscaled output afterward

Methodological note:

- the trusted target can be hindcast, GLORYS, or another current-conditions
  product
- the trusted target baseline file defines the horizontal grid and vertical
  levels
- an external GLORYS wet mask can define the ocean/coastline domain where fill
  is allowed; this is the current IPCC/ESGF biogeochemistry default
- when an external mask is used, the active fill domain is the union of that
  mask and cells already valid in the trusted baseline. This keeps the final
  output from dropping cells that the GLORYS-coast-filled hindcast baseline
  already owns, even if a mask slice has a small mismatch.
- the current IPCC/ESGF biogeochemistry path applies GLORYS-mask coastal fill
  twice in separate steps:
  1. while building the full hindcast baseline root
     `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast`
  2. while repairing remapped IPCC/ESGF anomaly gaps before adding them to that
     baseline
- the fill is applied to the baseline product and to the anomaly product, not
  to the final absolute field after addition
- the current default method is distance-weighted fill on the trusted target
  grid and allowed wet mask, intended to reduce unresolved empty coastal target
  cells more smoothly than a pure nearest-value fill
- the current implementation keeps that same distance-weighted philosophy but
  speeds it up by reusing precomputed local donor geometry on the trusted
  target mask, rather than recomputing donor neighborhoods from scratch for
  each missing coastal cell
- donor values are read from the original finite source field for each fill
  pass; cells created by interpolation are not allowed to become donors in the
  same pass
- for current IPCC/ESGF biogeochemistry, `COASTAL_FILL_REQUIRE_COMPLETE=yes`
  is enabled by default after that bounded fill. This is a deliberate
  force-complete fallback: any anomaly cells still missing inside the allowed
  GLORYS-plus-baseline domain are filled by local propagation from neighboring
  already-repaired anomaly cells so the final future product keeps the same
  coastal domain as the fixed hindcast baseline.
- if local propagation still cannot find any connected anomaly donor,
  `COASTAL_FILL_COMPLETE_FALLBACK_VALUE=0` assigns a zero anomaly to the
  remaining allowed-domain cells. In the additive workflow this means the fixed
  hindcast baseline is carried forward unchanged at those cells.
- the force-complete fallback is a methodological assumption. It prioritizes
  shared GLORYS-mask coverage for coastal species products over leaving tiny
  unresolved IPCC/ESGF anomaly holes as missing values. The zero-anomaly
  fallback is stronger than interpolation: it assumes no modeled future change
  where no anomaly donor exists. This is not a conservative remapping method
  and should be revisited if coastal anomaly gradients become a central
  validation target.
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
- `COASTAL_FILL_REQUIRE_COMPLETE`
  - `yes` forces remaining missing anomaly cells inside the wet mask to be
    locally propagated after the bounded fill
  - generic default is `no`
  - current IPCC/ESGF biogeochemistry wrapper default is `yes`
- `COASTAL_FILL_COMPLETE_FALLBACK_VALUE`
  - numeric fallback assigned to any anomaly cells still missing after local
    propagation when complete coverage is required
  - current IPCC/ESGF biogeochemistry wrapper default is `0`

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
- the current CESM coastal-fill worker writes member-aware outputs under:
  `/home/SB5/downscaled/cesm_f09_g16/<member>/rcp85/<var>/0p05/<window>/`
  while preserving the full original CESM member string in each filename

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

Current source roots:

- all future products are read from the final downscaled archive:
  `/home/SB5/downscaled/<model>/<realization>/<scenario>/<var>/...`
- for current IPCC/ESGF biogeochemistry products, this includes paths such as
  `/home/SB5/downscaled/CNRM-ESM2-1/r1i1p1f2/ssp585/chl/...`
- for current CESM physical products, this includes paths such as
  `/home/SB5/downscaled/cesm_f09_g16/001/rcp85/thetao/...`
- `/home/SB5/downscaled_rcp85/<var>/...` is retained only as a legacy fallback
  while older outputs are still present

By default, `MODEL=auto`, `REALIZATION=auto`, and `SCENARIO=auto` copy every
matching future product for each variable/window. Set selectors explicitly to
copy only one branch:

```bash
MODEL=CNRM-ESM2-1 REALIZATION=r1i1p1f2 SCENARIO=ssp585 ./scripts/runners/products/run_organize_ocean_downscaling_products.sh
```

The Slurm runner can also be scoped to a subset of variables, scopes, and
future windows. For example, to refresh only `chl`, `o2`, and `ph`
baseline/current products plus the three CNRM future windows after rebuilding
the GLORYS-coast biogeochemistry products:

```bash
ORGANIZE_SCOPES="baseline future" \
BASELINE_VARS="chl o2 ph" \
VARS="chl o2 ph" \
WINDOWS="2030-2060 2050-2060 2090-2100" \
MODEL=CNRM-ESM2-1 \
REALIZATION=r1i1p1f2 \
SCENARIO=ssp585 \
HINDCAST_0P05_ROOT=/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast \
DOWNSCALED_ROOT=/home/SB5/downscaled \
PRODUCT_ROOT=/home/SB5/ocean_downscaling_products \
OVERWRITE=yes \
bash scripts/runners/products/run_organize_ocean_downscaling_products.sh
```

For one CESM member:

```bash
MODEL=cesm_f09_g16 REALIZATION=002 SCENARIO=rcp85 ./scripts/runners/products/run_organize_ocean_downscaling_products.sh
```

The organizer is incremental by default. If a destination folder or baseline
file already contains NetCDF output, it is skipped. To refresh existing curated
products, run with:

```bash
OVERWRITE=yes ./scripts/runners/products/run_organize_ocean_downscaling_products.sh
```

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
│   ├── ph/
│   │   ├── 0p25/
│   │   └── 0p05/
│   ├── mlotst/
│   │   └── 0p05/
│   ├── so/
│   │   └── 0p05/
│   ├── thetao/
│   │   └── 0p05/
│   ├── uo/
│   │   └── 0p05/
│   ├── vo/
│   │   └── 0p05/
│   └── zos/
│       └── 0p05/
└── future/
    └── <model>/
        └── <realization>/
            └── <scenario>/
                └── <var>/
                    └── <window>/
                        ├── 0p05/
                        └── 0p25/
```

Notes:

- `baseline/` stores curated climatological reference products
- baseline products are now organized by resolution when available
- biogeochemistry variables can include both `0p25` and derived `0p05`
  hindcast baseline products; the current preferred `0p05` baseline source is
  the GLORYS-coast-filled hindcast root
- `thetao`, `so`, `uo`, `vo`, `zos`, `mlotst`, and `siconc` contribute `0p05` baseline
  products from the GLORYS reference branch when those climatologies exist
- default baseline variables are:
  `chl`, `o2`, `ph`, `thetao`, `so`, `uo`, `vo`, `zos`, `mlotst`, and
  `siconc`
- default future variables are:
  `thetao`, `so`, `ph`, `o2`, `chl`, `uo`, `vo`, `zooc`, `zos`, `mlotst`,
  and `siconc`
- `zooc` is future-only in the current product workflow; it is not included in
  the default baseline set
- `future/` stores curated future/downscaled products
- future products preserve model, realization/member-or-statistic, scenario,
  variable, window, and resolution
- the runner now submits one Slurm job per curated subtree:
  - `baseline/<var>`
  - `future/<var>/<window>` copy tasks, which may populate multiple
    `future/<model>/<realization>/<scenario>/...` branches when selectors are
    left as `auto`
- within each submitted job, the tool can copy multiple NetCDF files in
  parallel using the allocated CPUs
- existing destination NetCDF files are skipped unless `OVERWRITE=yes`
- future branches preserve both `0p25` and `0p05` products
  under each future window when that layout exists
- the tool copies files; it does not move or delete the original workflow trees

### Original Derived Hindcast Baseline 0.05 Tree

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
- remaps to the same GLORYS `0.05` grid description, but does not fill the
  hindcast coastline to the GLORYS wet mask
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

This original `0p05` root is kept for reproducibility and comparison. The
current preferred biogeochemistry baseline for downscaling is the
GLORYS-coast-filled root described below.

### GLORYS-Coast Hindcast Baseline 0.05 Tree

Built with:

- [remap_hindcast_baseline_to_0p05_glorys_coast.sh](scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh)
- [run_remap_hindcast_baseline_to_0p05_glorys_coast.sh](scripts/runners/products/run_remap_hindcast_baseline_to_0p05_glorys_coast.sh)

Expected output root:

```text
/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast/
└── <var>/
    └── clim_windows/
```

Notes:

- derives an all-variable `0.05 x 0.05` hindcast biogeochemistry baseline from
  the existing `0.25 x 0.25` hindcast climatology tree
- first remaps each variable to the GLORYS `0.05` grid with `cdo`
- then fills missing coastal cells inside the GLORYS wet mask, currently using:
  `/home/SB5/glorys12v1_monthly_0p05/thetao/clim_windows/glorys12v1_thetao_clim_2006-2014.nc`
- `COASTAL_FILL_REQUIRE_COMPLETE=yes` is now the default for this GLORYS-coast
  baseline builder. After the bounded nearest or distance-weighted fill, any
  remaining GLORYS-wet baseline gaps are locally propagated from neighboring
  finite baseline values. If disconnected mask breaks still remain, the final
  fallback uses the nearest finite baseline donor in the same 2-D field. This
  is intentionally not a zero fallback.
- keeps the same variable-folder and `clim_windows/` structure:
  `chl`, `fe`, `no3`, `nppv`, `o2`, `ph`, `phyc`, `po4`, and `si` are
  expected when all current hindcast biogeochemistry variables are present
- output filenames add the suffix `_grid_0p05_global.nc`
- the runner submits one Slurm job per variable directory
- `EXCLUDE_NODES` or `SBATCH_EXCLUDE` can be set to pass an `--exclude` list to
  `sbatch` when a cluster node is unhealthy
- outputs are NetCDF4/zlib-compressed, so file size differences from the
  original `0p05` tree are expected; use valid/missing cell counts for coverage
  checks
- this root is now the default `BASELINE_ROOT` for the IPCC/ESGF-to-hindcast
  coastal-fill downscaling runners

### Curated depth-layer NetCDF tree

Built with:

- [aggregate_ocean_downscaling_products_by_depth_bins.sh](scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh)
- [run_aggregate_ocean_downscaling_products_fine_layers.sh](scripts/runners/products/run_aggregate_ocean_downscaling_products_fine_layers.sh)

Expected output root:

```text
/home/SB5/ocean_downscaling_products_layers/
├── baseline/
│   └── <var>/<resolution>/
└── future/
    └── <model>/<realization>/<scenario>/<var>/<window>/<resolution>/
```

Notes:

- mirrors the curated `baseline/future` structure, including model,
  realization/member/statistic, scenario, window, and resolution for future
  products
- each 3D NetCDF file becomes one NetCDF file per fine depth interval
- the runner submits one job per main subtree:
  - `baseline/<var>`
  - `future/<model>`
- within each submitted job, the tool still parallelizes over files
- `OVERWRITE=no` by default skips existing layer products; set
  `OVERWRITE=yes` to refresh them
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
- the current tool uses file-level parallelism and is configured to use `5`
  CPUs per Slurm task
- output filenames follow patterns such as:
  - `global_ocean_biogeochemistry_hindcast_chl_clim_2006-2014_layer_0000_0025m.nc`
  - `ipcc_esgf_CNRM-ESM2-1_ssp585_r1i1p1f2_to_hindcast_chl_downscaled_2050-2060_grid_0p05_global_layer_1000_1500m.nc`

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
│   └── <var>/<resolution>/
└── future/
    └── <model>/<realization>/<scenario>/<var>/<window>/<resolution>/
```

Notes:

- mirrors the curated `baseline/future` structure, including model,
  realization/member/statistic, scenario, window, and resolution for future
  products
- each 3D NetCDF file becomes one NetCDF file per pelagic zone
- the runner submits one job per main subtree:
  - `baseline/<var>`
  - `future/<model>`
- within each submitted job, the tool still parallelizes over files
- `OVERWRITE=no` by default skips existing pelagic products; set
  `OVERWRITE=yes` to refresh them
- current zones are:
  - `epipelagic` for `[0,200)`
  - `mesopelagic` for `[200,1000)`
  - `bathypelagic` for `[1000,4000)`
  - `abyssopelagic` for `[4000,6000)`
- the same weighting and single-level fallback rules used for fine layers also
  apply here
- the current tool uses file-level parallelism and is configured to use `5`
  CPUs per Slurm task
- output filenames follow patterns such as:
  - `global_ocean_biogeochemistry_hindcast_chl_clim_2006-2014_zone_epipelagic_0000_0200m.nc`
  - `b.e11.BRCP85C5CNBDRD.f09_g16.001.pop.h.TEMP.200601-210012.1deg_on_glorys_downscaled_thetao_2050-2060_zone_bathypelagic_1000_4000m.nc`

Method note:

- the same vertical-weighting assumption used for fine depth layers applies
  here as well
- pelagic-zone means therefore depend on either explicit vertical bounds or
  reconstructed bounds from the shared depth-center coordinate

### Curated Parquet trees

Built with:

- [export_ocean_downscaling_products_to_parquet.sh](scripts/tools/export_ocean_downscaling_products_to_parquet.sh)
- [run_export_ocean_downscaling_products_layers_to_parquet.sh](scripts/runners/products/run_export_ocean_downscaling_products_layers_to_parquet.sh)
- [run_export_ocean_downscaling_products_pelagic_to_parquet.sh](scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_parquet.sh)
- [run_export_ocean_downscaling_products_depths_to_parquet.sh](scripts/runners/products/run_export_ocean_downscaling_products_depths_to_parquet.sh)

Expected output roots:

```text
/home/SB5/ocean_downscaling_products_layers_parquet/
/home/SB5/ocean_downscaling_products_pelagic_parquet/
/home/SB5/ocean_downscaling_products_bydepth_parquet/
/home/SB5/ocean_downscaling_products_depths_parquet/
```

Notes:

- mirrors the fine-layer, pelagic, or individual-depth NetCDF tree
- exports each 2D NetCDF file to one Parquet table
- the runners submit one job per main subtree:
  - `baseline/<var>`
  - `future/<model>`
- within each submitted job, the tool parallelizes over files and is
  configured to use `5` CPUs per Slurm task
- `OVERWRITE=no` by default skips existing Parquet products; set
  `OVERWRITE=yes` to refresh them
- the individual-depth Parquet runner mirrors the split-depth root selection:
  empty or `all` `MAX_DEPTH_M` reads `/home/SB5/ocean_downscaling_products_bydepth`
  and writes `/home/SB5/ocean_downscaling_products_bydepth_parquet`; a bounded
  value such as `MAX_DEPTH_M=600` reads `/home/SB5/ocean_downscaling_products_depths`
  and writes `/home/SB5/ocean_downscaling_products_depths_parquet`
- Parquet columns are:
  - `x`
  - `y`
  - `depth`
  - `<variable>_<units>`
- for fine-layer and pelagic exports, `depth` is a layer or zone label; for
  individual-depth exports, `depth` is the numeric depth in meters
- this remains the current tabular final delivery export

### Curated layer and pelagic GeoTIFF trees

Built with:

- [export_ocean_downscaling_products_to_geotiff.sh](scripts/tools/export_ocean_downscaling_products_to_geotiff.sh)
- [run_export_ocean_downscaling_products_layers_to_geotiff.sh](scripts/runners/products/run_export_ocean_downscaling_products_layers_to_geotiff.sh)
- [run_export_ocean_downscaling_products_pelagic_to_geotiff.sh](scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_geotiff.sh)

Expected output roots:

```text
/home/SB5/ocean_downscaling_products_layers_geotiff/
/home/SB5/ocean_downscaling_products_pelagic_geotiff/
```

Notes:

- mirrors the fine-layer or pelagic NetCDF tree
- exports each 2D NetCDF file to one compressed GeoTIFF
- encodes floating-point values as integer rasters with:
  `stored_value = round(real_value * scale_factor)`
- downstream apps recover real values with:
  `real_value = stored_value / scale_factor`
- default scale factors are variable-aware:
  - `thetao`, `TEMP`, `so`, `SALT`, `uo`, `UVEL`: `100`
  - `o2`, `O2`: `10`
  - `chl`, `CHL`: `10000`
- `ENCODE_DTYPE=auto` writes `Int16` when encoded values fit safely and
  promotes to `Int32` otherwise
- each export job writes a `geotiff_manifest.csv` containing source path,
  GeoTIFF path, variable, units, scale factor, encoded dtype, nodata value,
  real min/max, encoded min/max, compression, and CRS
- GeoTIFF export expects regular 1D `lon/lat`, `longitude/latitude`, or `x/y`
  coordinates; curvilinear inputs should be remapped before this delivery step

### Shiny-viewer sample GeoTIFF staging tree

Built with:

- [stage_ocean_downscaling_sample_products.sh](scripts/tools/stage_ocean_downscaling_sample_products.sh)
- [run_stage_ocean_downscaling_sample_products.sh](scripts/runners/products/run_stage_ocean_downscaling_sample_products.sh)

Expected output root:

```text
/home/SB5/ocean_downscaling_sample_products_geotiff/
├── layers/
│   ├── baseline/<var>/0p05/*.tif
│   └── future/<scenario>/<var>/<window>/0p05/*.tif
├── pelagic/
│   ├── baseline/<var>/0p05/*.tif
│   └── future/<scenario>/<var>/<window>/0p05/*.tif
├── depths/
│   ├── baseline/<var>/0p05/*.tif
│   └── future/<scenario>/<var>/<window>/0p05/*.tif
└── manifests/
    ├── layers_geotiff_manifest.csv
    ├── pelagic_geotiff_manifest.csv
    ├── depths_geotiff_manifest.csv
    └── geotiff_manifest.csv
```

Notes:

- this is a copy-only staging step for viewer deployment tests
- it reads from the layer, pelagic, and individual-depth GeoTIFF trees
- it only stages `0p05` products
- future outputs are staged by `scenario/variable/window/resolution` for the
  Shiny app, while the manifests retain `model`, `realization`, `scenario`,
  `variable`, `window`, and `resolution`
- when a future model/scenario/variable/window has multiple realizations, it
  keeps the first sorted realization only, so CESM currently stages member
  `001` and IPCC/ESGF currently stages `r1i1p1f2`
- it stages filtered manifests for the copied GeoTIFFs:
  - `layers_geotiff_manifest.csv`
  - `pelagic_geotiff_manifest.csv`
  - `depths_geotiff_manifest.csv`
  - `geotiff_manifest.csv`
- manifests preserve GeoTIFF scale/decode metadata so the Shiny app can recover
  physical values from integer rasters
- dry run is the default; use `DRY_RUN=no` to copy files

Typical commands:

```bash
./scripts/runners/products/run_stage_ocean_downscaling_sample_products.sh
DRY_RUN=no ./scripts/runners/products/run_stage_ocean_downscaling_sample_products.sh
```

The individual-depth source can be disabled with `STAGE_DEPTHS=no`, but the
default is now to stage it from:

```text
/home/SB5/ocean_downscaling_products_depths_geotiff
```

### Curated by-depth NetCDF and GeoTIFF trees

Built with:

- [split_ocean_downscaling_products_by_depth.sh](scripts/tools/split_ocean_downscaling_products_by_depth.sh)
- [run_split_ocean_downscaling_products_by_depth.sh](scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh)

Default all-depth NetCDF output root:

```text
/home/SB5/ocean_downscaling_products_bydepth/
├── baseline/
└── future/
```

Shallow individual-depth roots for species workflows:

```text
/home/SB5/ocean_downscaling_products_depths/
/home/SB5/ocean_downscaling_products_depths_geotiff/
```

Notes:

- mirrors the curated `baseline/future` structure
- each 3D NetCDF file becomes one 2D NetCDF file per depth layer
- `MAX_DEPTH_M` can limit exported depth centers:
  - empty or `all` exports all depths
  - `600` exports only depth centers `<= 600 m`
- when `MAX_DEPTH_M` is set and `OUT_ROOT` is not, the runner writes NetCDFs to
  `/home/SB5/ocean_downscaling_products_depths`
- set `GEOTIFF=yes` or `GEOTIFF=true` to submit a dependent GeoTIFF export job
  after the NetCDF split succeeds
- the default GeoTIFF root is `${OUT_ROOT}_geotiff`, so the 600 m default is:
  `/home/SB5/ocean_downscaling_products_depths_geotiff`
- the current tool uses file-level parallelism and is configured to use `6`
  CPUs per Slurm task
- depth is encoded in the filename with a zero-padded safe token such as:
  - `depth_0000p494m`
  - `depth_0005p079m`
  - `depth_0453p938m`
  - `depth_5727p917m`
- depth tokens use `MIN_DECIMALS=3` by default; if two selected depth centers
  round to the same filename token, the splitter stops with an error and asks
  for a higher `MIN_DECIMALS` value

Typical commands:

```bash
# Original behavior: all depths to /home/SB5/ocean_downscaling_products_bydepth
bash scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh

# Species workflow: original depth slices through 600 m plus matching GeoTIFFs
MAX_DEPTH_M=600 \
GEOTIFF=yes \
bash scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh

# Export the matching shallow individual-depth NetCDF tree to Parquet
MAX_DEPTH_M=600 \
bash scripts/runners/products/run_export_ocean_downscaling_products_depths_to_parquet.sh
```

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
  `ipcc_esgf_CNRM-ESM2-1_historical_r1i1p1f2_chl_clim_2006-2014.nc`
  `ipcc_esgf_CNRM-ESM2-1_ssp585_r1i1p1f2_chl_clim_2030-2060.nc`
  `ipcc_esgf_CNRM-ESM2-1_ssp585_r1i1p1f2_chl_clim_2050-2060.nc`
  `ipcc_esgf_CNRM-ESM2-1_ssp585_r1i1p1f2_chl_clim_2090-2100.nc`

### Delta outputs

Examples:

- raw delta:
  `ipcc_esgf_CNRM-ESM2-1_ssp585_r1i1p1f2_chl_delta_2050-2060_minus_2006-2014.nc`
- regridded delta:
  `ipcc_esgf_CNRM-ESM2-1_ssp585_r1i1p1f2_chl_delta_2050-2060_minus_2006-2014_grid_0p25_global.nc`

### Downscaled outputs

Examples:

- native `0.05` downscaled output:
  `ipcc_esgf_CNRM-ESM2-1_ssp585_r1i1p1f2_to_hindcast_chl_downscaled_2050-2060_grid_0p05_global.nc`
- regridded `0.25` downscaled output:
  `ipcc_esgf_CNRM-ESM2-1_ssp585_r1i1p1f2_to_hindcast_chl_downscaled_2050-2060_grid_0p25_global.nc`
- current final downscaled path:
  `/home/SB5/downscaled/CNRM-ESM2-1/r1i1p1f2/ssp585/chl/0p05/2050-2060/`
- additional current future windows include:
  `/home/SB5/downscaled/CNRM-ESM2-1/r1i1p1f2/ssp585/chl/0p05/2030-2060/`
  and `/home/SB5/downscaled/CNRM-ESM2-1/r1i1p1f2/ssp585/chl/0p05/2090-2100/`
- current CESM final downscaled path:
  `/home/SB5/downscaled/cesm_f09_g16/001/rcp85/thetao/0p05/2050-2060/`

## Expected Cluster Paths

Common paths used in the current workflows include:

- `/home/sandbox-sparc/cesmle-ocn-fetch`
- `/home/sandbox-sparc/cesmle-ocn-fetch/bgc_monthly_0p25`
- `/home/SB5/glorys12v1_monthly_0p05`
- `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25`
- `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05`
- `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast`
- `/home/SB5/ipcc_esgf/downloads`
- `/home/SB5/ipcc_esgf/monthly_1deg`
- `/home/SB5/ipcc_esgf/cmip5_rcp85`
- `/home/SB5/downscaled`
- `/home/SB5/downscaled_rcp85` (legacy CESM physical downscaled root)
- `/home/SB5/ocean_downscaling_products`
- `/home/SB5/ocean_downscaling_products_layers`
- `/home/SB5/ocean_downscaling_products_pelagic`
- `/home/SB5/ocean_downscaling_products_depths`
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

- Future change is represented with an additive climatological change field
  computed within each model family, then applied to a trusted target baseline:
  `downscaled future = trusted target baseline + model-derived change field`.

- The hindcast climatology is treated as the historical baseline for the
  IPCC-to-hindcast downscaling branch.

- Vertical matching to the GLORYS reference grid is performed before the
  climatology and delta steps for branches where comparable vertical structure
  is required.

- For current IPCC/ESGF biogeochemistry downscaling, the target horizontal
  domain is the GLORYS `0.05` grid plus the GLORYS wet mask. GLORYS supplies
  the grid and coastline mask, not the biogeochemical values.

- The hindcast biogeochemistry baseline is first rebuilt from the `0.25`
  hindcast climatology tree into a complete `0.05` GLORYS-coast-filled
  baseline product. Future anomaly fields are then remapped and repaired
  against the same GLORYS wet mask plus any cells already valid in that fixed
  baseline before being added to it.
- Baseline completion and anomaly completion use different fallback meanings.
  Remaining GLORYS-wet baseline gaps are completed by local propagation from
  finite biogeochemistry baseline values, then by the nearest finite baseline
  donor if a GLORYS-wet cell is disconnected from local donors. Remaining
  anomaly gaps can use a zero anomaly fallback only after local propagation
  fails, which means carrying the fixed baseline forward unchanged.

- The current default coastal-fill method is distance-weighted interpolation.
  During a fill pass, donor values come from the original finite source field;
  newly filled cells are not reused as donors for other missing cells in that
  same pass.

- For current IPCC/ESGF biogeochemistry, the anomaly fill then requires
  complete coverage inside the allowed GLORYS-plus-baseline domain. Any anomaly
  cells still missing after the bounded distance-weighted pass are filled by
  local propagation from neighboring repaired anomaly cells. This is an
  explicit coverage assumption so future products share the same coastal domain
  as the fixed hindcast baseline.
- If no connected anomaly donor exists even after local propagation, the
  current IPCC/ESGF biogeochemistry path assigns a zero anomaly. This carries
  the fixed hindcast baseline forward unchanged at those cells.

- The final absolute future field is not horizontally filled after addition.
  The two repaired inputs are the GLORYS-coast baseline product and the
  remapped anomaly product.

- The coastal-fill implementation is target-mask-based, not a guarantee of
  fully conservative coastal behavior in every application. Its purpose here is
  to make the hindcast baseline and future anomaly fields share the same
  GLORYS-coast ocean domain before final addition.

- The force-complete baseline/anomaly fallback is not conservative remapping. It is a
  pragmatic choice for coastal biological delivery products where consistent
  wet-mask coverage is more important than preserving tiny unresolved anomaly
  holes from coarse IPCC/ESGF source fields. The zero-anomaly fallback should be
  treated as a caveat in any interpretation of fine coastal anomaly patterns.

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

## Next Steps For Future Statistical Improvements

The most useful future additions would be small validation and sensitivity
checks around the current change-field method, not a full empirical-statistical
downscaling framework.

- Validation first: add a historical pseudo-future test. For example, use an
  earlier model window to predict a later observed, hindcast, or GLORYS window,
  then compare the predicted field against the trusted target. Useful metrics
  include bias, RMSE/MAE, spatial correlation, and possibly quantile error. This
  would show whether the current method is already good enough.

- Variable-specific delta modes: keep additive deltas for `thetao`, probably
  `so`, and velocities depending on interpretation. For `chl`, test
  multiplicative or log-ratio deltas:

  ```text
  downscaled = baseline * future_model / historical_model
  log(downscaled) = log(baseline) + [log(future_model) - log(historical_model)]
  ```

  This is likely more useful than adding GLMs, analogs, or neural networks.

- Distribution check, not full quantile mapping: full daily or monthly quantile
  mapping is probably unnecessary if temporal structure is not needed. A simpler
  check can compare baseline and future distributions by depth or region and
  flag cases where additive deltas create strange values, compressed
  variability, or negative `chl`/`o2`.

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

- `delta_from_climatologies.slurm.sh` computes model-derived change-field
  products; it does not add them to a baseline.

- `add_anomaly_to_baseline.slurm.sh` and
  `add_anomaly_to_baseline_with_coastal_fill.slurm.sh` are the final
  addition/downscaling workers.
  They combine a baseline climatology with an anomaly/delta field. In the
  current IPCC/ESGF biogeochemistry path, the coastal-fill variant reads the
  GLORYS-coast-filled hindcast baseline and repairs missing remapped anomaly
  cells inside the GLORYS wet mask plus any baseline-valid cells before
  addition. That branch now requires complete anomaly coverage inside that
  allowed domain, using local propagation for any cells still missing after the
  bounded donor search.

- The downscaling part of the overall workflow still continues after
  climatologies. Climatologies are not the final product; they are the inputs to
  later anomaly, delta, and downscaling stages.

- Final downscaled future products now use
  `/home/SB5/downscaled/<model>/<realization>/<scenario>/<var>/...`.
  For the current CMIP6/IPCC workflow this can include the five selected
  models, first available members, `ssp126`, `ssp245`, and `ssp585`, and the
  expanded future variables. For example:
  `/home/SB5/downscaled/CNRM-ESM2-1/r1i1p1f2/ssp585/chl/...`.
  CESM physical products use the same final provenance order, for example:
  `/home/SB5/downscaled/cesm_f09_g16/001/rcp85/thetao/...`. The older
  `/home/SB5/downscaled_rcp85` root remains a legacy fallback for physical
  products during transition.

- IPCC/ESGF filenames still carry model, scenario, and member provenance, and
  the final downscaled tree also exposes the realization/member as a directory
  level so multiple models, members, and scenarios can coexist cleanly.

- 3D CMIP6/IPCC variables go through `parts/`, `on_glorys/`,
  `clim_windows/`, and `delta_windows/`. 2D variables such as `zos`, `mlotst`,
  and `siconc` skip `on_glorys/` and compute climatologies directly from
  `parts/`.

- `siconc` is included in both the GLORYS baseline and future/product side of
  the workflow. `zooc` is included in the future/product side only until a
  trusted baseline is configured.
