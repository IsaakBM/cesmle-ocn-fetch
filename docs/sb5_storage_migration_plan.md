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
`delta_windows`, and `delta_windows_0p25`.

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

## Non-Destructive Setup

Run:

```bash
bash scripts/bash/prepare_sb5_storage_layout.sh
```

This script only creates directories with `mkdir -p`.
