#!/usr/bin/env bash
# ==============================================================================
#  Compatibility wrapper for the generic trusted-baseline coastal-fill runner
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERIC_RUNNER="${SCRIPT_DIR}/../downscaling/run_add_anomaly_to_trusted_baseline_with_coastal_fill.sh"

DATASET_LABEL="${DATASET_LABEL:-ipcc_esgf_to_hindcast}" \
BASELINE_ROOT="${BASELINE_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05}" \
BASELINE_FILE_TEMPLATE="${BASELINE_FILE_TEMPLATE:-__BASELINE_ROOT__/__VAR__/clim_windows/global_ocean_biogeochemistry_hindcast___VAR___clim___BASELINE_TAG___grid_0p05_global.nc}" \
ANOMALY_ROOT="${ANOMALY_ROOT:-/home/SB5/ipcc_esgf_monthly_1deg/ssp585}" \
ANOMALY_FILE_TEMPLATE="${ANOMALY_FILE_TEMPLATE:-__ANOMALY_ROOT__/__SRC_VAR__/delta_windows_0p25/ipcc_esgf_ssp585___SRC_VAR___delta___WINDOW___minus___BASELINE_TAG___grid_0p25_global.nc}" \
ANOMALY_GRIDFILE="${ANOMALY_GRIDFILE:-/home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt}" \
REGRID_GRIDFILE="${REGRID_GRIDFILE:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/grid_0p25_global.txt}" \
REGRID_SUFFIX="${REGRID_SUFFIX:-grid_0p25_global}" \
exec "${GENERIC_RUNNER}" "$@"
