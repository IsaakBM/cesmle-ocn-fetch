#!/usr/bin/env bash
# ==============================================================================
#  Prepare SB5 storage layout
#
#  Ownership:
#    This code was created by Isaac Brito-Morales
#    (ibrito@conservation.org)
#
#  Purpose:
#    Create the agreed non-destructive /home/SB5 directory layout for
#    reanalysis products and IPCC/ESGF climate-model products.
#
#  Notes:
#    - This script only runs mkdir -p.
#    - It does not move, delete, rename, or symlink existing data.
# ==============================================================================

set -euo pipefail

SB5_ROOT="${SB5_ROOT:-/home/SB5}"

mkdir -p \
  "${SB5_ROOT}/reanalysis/glorys12v1/monthly_0p05" \
  "${SB5_ROOT}/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25" \
  "${SB5_ROOT}/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05" \
  "${SB5_ROOT}/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast" \
  "${SB5_ROOT}/ipcc_esgf/downloads" \
  "${SB5_ROOT}/ipcc_esgf/monthly_1deg" \
  "${SB5_ROOT}/ipcc_esgf/cmip5_rcp85"

echo "Prepared SB5 storage layout under: ${SB5_ROOT}"
echo "No files were moved, deleted, renamed, or symlinked."
