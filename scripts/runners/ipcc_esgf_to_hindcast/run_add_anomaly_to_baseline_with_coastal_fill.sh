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
DISCOVERY_LIB="${SCRIPT_DIR}/../../lib/ipcc_esgf_discovery.sh"

# shellcheck source=../../lib/ipcc_esgf_discovery.sh
source "${DISCOVERY_LIB}"

IPCC_ROOT="${IPCC_ROOT:-/home/SB5/ipcc_esgf_monthly_1deg}"
MEMBER="${MEMBER:-auto}"

mapfile -t DISCOVERED_GROUPS < <(ipcc_esgf_discover_monthly_groups "${IPCC_ROOT}" "delta_windows_0p25" | awk -F '\t' '$2 ~ /^ssp[0-9][0-9][0-9]$/' | sort -u)

if (( ${#DISCOVERED_GROUPS[@]} == 0 )); then
  echo "ERROR: No IPCC/ESGF future delta groups discovered under: ${IPCC_ROOT}"
  exit 1
fi

echo "Submitting IPCC/ESGF-to-hindcast coastal-fill downscaling jobs:"
for group in "${DISCOVERED_GROUPS[@]}"; do
  IFS=$'\t' read -r model scenario var <<< "$group"
  delta_dir="${IPCC_ROOT}/${model}/${scenario}/${var}/delta_windows_0p25"

  member="$(ipcc_esgf_resolve_product_member "$delta_dir" "$model" "$scenario" "$var" "*.nc")" || {
    status=$?
    [[ "$status" -eq 2 ]] && continue
    exit "$status"
  }

  dataset_label="${DATASET_LABEL_PREFIX:-ipcc_esgf_${model}_${scenario}_${member}_to_hindcast}"

  DATASET_LABEL="${dataset_label}" \
  MODEL_LABEL="${model}" \
  SCENARIO_LABEL="${scenario}" \
  VAR_MAP_SPEC="${var}:${var}" \
  BASELINE_ROOT="${BASELINE_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05}" \
  BASELINE_FILE_TEMPLATE="${BASELINE_FILE_TEMPLATE:-__BASELINE_ROOT__/__TGT_VAR__/clim_windows/global_ocean_biogeochemistry_hindcast___TGT_VAR___clim___BASELINE_TAG___grid_0p05_global.nc}" \
  ANOMALY_ROOT="${IPCC_ROOT}/${model}/${scenario}" \
  ANOMALY_FILE_TEMPLATE="${ANOMALY_FILE_TEMPLATE:-__ANOMALY_ROOT__/__SRC_VAR__/delta_windows_0p25/ipcc_esgf_${model}_${scenario}_${member}___SRC_VAR___delta___WINDOW___minus___BASELINE_TAG___grid_0p25_global.nc}" \
  OUTROOT="${OUTROOT:-/home/SB5/downscaled}" \
  ANOMALY_GRIDFILE="${ANOMALY_GRIDFILE:-/home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt}" \
  COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD:-distance_weighted}" \
  COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER:-2.0}" \
  COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS:-4}" \
  REGRID_GRIDFILE="${REGRID_GRIDFILE:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/grid_0p25_global.txt}" \
  REGRID_SUFFIX="${REGRID_SUFFIX:-grid_0p25_global}" \
  "${GENERIC_RUNNER}" "$@"
done

echo "Done."
