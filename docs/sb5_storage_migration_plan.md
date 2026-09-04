# SB5 Storage Migration Plan

## Ownership

This plan was created by Isaac Brito-Morales (ibrito@conservation.org).

## Purpose

Define a cleaner `/home/SB5` storage layout before expanding CMIP6/IPCC model
downloads and processing. This plan is intentionally non-destructive: it does
not require moving, deleting, or symlinking existing data yet.

## Agreed Boundaries

Do not reorganize these roots during the first migration step:

- `/home/SB5/downscaled`
- `/home/SB5/ocean_downscaling_products*`

These already represent immediate downscaling outputs and delivery products.

## Target Layout

### Reanalysis And Baseline Products

Use `/home/SB5/reanalysis` for trusted present-day reanalysis, hindcast, and
baseline variants.

```text
/home/SB5/reanalysis/glorys12v1/monthly_0p05
/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25
/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05
/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast
```

### IPCC / ESGF Climate-Model Products

Use `/home/SB5/ipcc_esgf` for CMIP/IPCC model downloads, harmonized monthly
products, climatologies, and legacy CMIP5 RCP85 products.

```text
/home/SB5/ipcc_esgf/downloads
/home/SB5/ipcc_esgf/monthly_1deg
/home/SB5/ipcc_esgf/cmip5_rcp85
```

New CMIP6 downloads should use this layout:

```text
/home/SB5/ipcc_esgf/downloads/<model>/<member>/<experiment>/<variable>
```

New CMIP6 processed products should use this layout:

```text
/home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<experiment>/<variable>/<stage>
```

where `<stage>` may include `parts`, `on_glorys`, `clim_windows`,
`delta_windows`, `delta_windows_0p05` for GLORYS-target anomalies, and
`delta_windows_0p25` for hindcast-target anomalies.

## Current-To-Target Map

| Current root | Target root |
|---|---|
| `/home/SB5/glorys12v1_monthly_0p05` | `/home/SB5/reanalysis/glorys12v1/monthly_0p05` |
| `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25` | `/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25` |
| `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05` | `/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05` |
| `/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast` | `/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast` |
| `/home/SB5/ipcc_esgf_downloads` | `/home/SB5/ipcc_esgf/downloads` |
| `/home/SB5/ipcc_esgf_monthly_1deg` | `/home/SB5/ipcc_esgf/monthly_1deg` |
| `/home/SB5/rcp85` | `/home/SB5/ipcc_esgf/cmip5_rcp85` |

## Safe Migration Sequence

1. Create the target directories only.
2. Update scripts to accept environment-variable roots for new paths.
3. Start new CMIP6 fetches in `/home/SB5/ipcc_esgf/downloads`.
4. Keep existing data in place until downstream scripts are confirmed on the
   new layout.
5. Later, decide whether to move old data, leave it archived, or add symlinks.

## Dry-Run Migration Assessment

Before changing any legacy top-level roots, run the read-only assessment script
on the cluster:

```bash
bash scripts/bash/assess_sb5_storage_migration.sh
```

The report compares each legacy root with its agreed target root by existence,
size, shallow file counts, inode identity, top-level directory counts, sample
files, and symlinks. It also writes a commented dry-run compatibility-action
file. That file is intentionally not executable migration logic; it is a review
aid for choosing whether each legacy path should remain as-is, become an alias,
or eventually move into an archive namespace.

Current assessment from the cluster shows that the major target roots are
already populated as separate directories rather than identical inodes. Most
pairs match by size and shallow file count. The GLORYS target has more files
than the old root because it includes `siconc` and additional temporary files:

```text
/home/SB5/glorys12v1_monthly_0p05
  variables: bottomT, mlotst, so, thetao, uo, vo, zos
  files at maxdepth 4: 2276

/home/SB5/reanalysis/glorys12v1/monthly_0p05
  variables: bottomT, mlotst, siconc, so, thetao, uo, vo, zos
  files at maxdepth 4: 2601
```

This means the next migration decision should be about compatibility policy,
not moving bytes. Keep the legacy roots in place until at least one end-to-end
workflow has been tested using only the new default paths.

## New-Defaults Smoke Test

After updating script defaults to the target roots, run one small workflow test
from the cluster repo checkout. Start with the preflight check, which is
read-only and submits no Slurm jobs:

```bash
STEP=preflight bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
```

For a one-variable test of the GLORYS-target branch:

```bash
SMOKE_VARS=thetao STEP=preflight bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
SMOKE_VARS=thetao RUN=yes STEP=monthly bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
SMOKE_VARS=thetao RUN=yes STEP=audit bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
SMOKE_VARS=thetao RUN=yes STEP=vertical bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
SMOKE_VARS=thetao RUN=yes STEP=climatology bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
SMOKE_VARS=thetao RUN=yes STEP=delta bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
SMOKE_VARS=thetao RUN=yes STEP=add bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
```

For a one-variable test of the hindcast-target branch, use `SMOKE_VARS=chl`
with the same sequence. Wait for the Slurm jobs from each stage to finish before
starting the next stage. Do not use `STEP=all` for migration validation unless
all upstream stage outputs already exist.

Cluster validation completed on 2026-09-04:

- `thetao` GLORYS-target add-stage smoke test passed with Slurm job `1095795`.
  It read the new GLORYS and IPCC/ESGF roots and wrote the expected `0p05`
  downscaled product under `/home/SB5/downscaled`.
- `chl` hindcast-target add-stage smoke test passed with Slurm job `1095819`.
  It read the new GLORYS, hindcast, and IPCC/ESGF roots, used `log_ratio`
  anomaly mode, wrote the expected `0p05` downscaled product, and wrote the
  expected final `0p25` regridded product under `/home/SB5/downscaled`.

## Non-Destructive Setup

Run:

```bash
bash scripts/bash/prepare_sb5_storage_layout.sh
```

This script only creates directories with `mkdir -p`.
