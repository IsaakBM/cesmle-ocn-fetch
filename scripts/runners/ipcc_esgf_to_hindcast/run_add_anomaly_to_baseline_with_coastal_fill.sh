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

IPCC_ESGF_ROOT="${IPCC_ESGF_ROOT:-/home/SB5/ipcc_esgf}"
IPCC_ROOT="${IPCC_ROOT:-${IPCC_ESGF_ROOT}/monthly_1deg}"
MEMBER="${MEMBER:-auto}"
BASELINE_TAG="${BASELINE_TAG:-2006-2014}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/glorys12v1_monthly_0p05}"
HINDCAST_ROOT="${HINDCAST_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast}"
COASTAL_MASK_FILE="${COASTAL_MASK_FILE:-${GLORYS_ROOT}/thetao/clim_windows/glorys12v1_thetao_clim_${BASELINE_TAG}.nc}"
COASTAL_MASK_VAR="${COASTAL_MASK_VAR:-thetao}"
FILL_BASELINE_COASTAL_GAPS="${FILL_BASELINE_COASTAL_GAPS:-no}"
FILL_TOP_MISSING_ANOMALY="${FILL_TOP_MISSING_ANOMALY:-yes}"
COASTAL_MASK_VARS="${COASTAL_MASK_VARS:-all}"
COASTAL_FILL_REQUIRE_COMPLETE="${COASTAL_FILL_REQUIRE_COMPLETE:-yes}"
COASTAL_FILL_COMPLETE_FALLBACK_VALUE="${COASTAL_FILL_COMPLETE_FALLBACK_VALUE:-0}"
ANOMALY_MODE="${ANOMALY_MODE:-additive}"
ANOMALY_MODE_SPEC="${ANOMALY_MODE_SPEC:-chl=log_ratio}"
GLORYS_BASELINE_VARS="${GLORYS_BASELINE_VARS:-thetao so uo vo zos mlotst siconc}"
HINDCAST_BASELINE_VARS="${HINDCAST_BASELINE_VARS:-chl o2 ph}"

uses_coastal_mask() {
  local candidate="$1"
  local mask_var

  if [[ "${COASTAL_MASK_VARS}" == "all" ]]; then
    return 0
  fi

  for mask_var in ${COASTAL_MASK_VARS}; do
    if [[ "$candidate" == "$mask_var" ]]; then
      return 0
    fi
  done

  return 1
}

contains_word() {
  local needle="$1"
  shift
  local candidate

  for candidate in "$@"; do
    if [[ "$candidate" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

read -r -a GLORYS_BASELINE_VAR_LIST <<< "${GLORYS_BASELINE_VARS}"
read -r -a HINDCAST_BASELINE_VAR_LIST <<< "${HINDCAST_BASELINE_VARS}"

mapfile -t DISCOVERED_GROUPS < <(ipcc_esgf_discover_monthly_groups_any_layout "${IPCC_ROOT}" "delta_windows_0p25" | awk -F '\t' '$3 ~ /^ssp[0-9][0-9][0-9]$/' | sort -u)

if (( ${#DISCOVERED_GROUPS[@]} == 0 )); then
  echo "ERROR: No IPCC/ESGF future delta groups discovered under: ${IPCC_ROOT}"
  exit 1
fi

echo "Submitting IPCC/ESGF-to-hindcast coastal-fill downscaling jobs:"
for group in "${DISCOVERED_GROUPS[@]}"; do
  IFS=$'\t' read -r model member scenario var <<< "$group"
  if ! delta_dir="$(ipcc_esgf_monthly_stage_dir_for_group "$IPCC_ROOT" "$model" "$member" "$scenario" "$var" "delta_windows_0p25")"; then
    echo "WARN: Delta directory not found, skipping MODEL=${model} MEMBER=${member} SCENARIO=${scenario} VAR=${var}"
    continue
  fi
  var_dir="$(dirname "$delta_dir")"
  anomaly_root="$(dirname "$var_dir")"

  member="$(ipcc_esgf_resolve_product_member "$delta_dir" "$model" "$scenario" "$var" "*.nc")" || {
    status=$?
    [[ "$status" -eq 2 ]] && continue
    exit "$status"
  }

  dataset_label="${DATASET_LABEL_PREFIX:-ipcc_esgf_${model}_${scenario}_${member}_to_hindcast}"
  baseline_root="$HINDCAST_ROOT"
  baseline_file_template="__BASELINE_ROOT__/__TGT_VAR__/clim_windows/global_ocean_biogeochemistry_hindcast___TGT_VAR___clim___BASELINE_TAG___grid_0p05_global.nc"
  anomaly_gridfile="${GLORYS_ROOT}/grid_0p05_global.txt"
  regrid_gridfile="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/grid_0p25_global.txt"
  regrid_suffix="grid_0p25_global"
  target_label="hindcast"
  coastal_mask_file_for_var=""
  coastal_mask_var_for_var=""
  fill_baseline_gaps_for_var="no"

  if contains_word "$var" "${GLORYS_BASELINE_VAR_LIST[@]}"; then
    dataset_label="${DATASET_LABEL_PREFIX:-ipcc_esgf_${model}_${scenario}_${member}_to_glorys}"
    baseline_root="$GLORYS_ROOT"
    baseline_file_template="__BASELINE_ROOT__/__TGT_VAR__/clim_windows/glorys12v1___TGT_VAR___clim___BASELINE_TAG__.nc"
    target_label="glorys"
  elif ! contains_word "$var" "${HINDCAST_BASELINE_VAR_LIST[@]}"; then
    echo "WARN: No trusted target baseline configured for VAR=${var}; leaving at delta stage."
    continue
  fi

  if [[ "$target_label" == "hindcast" ]] && uses_coastal_mask "$var"; then
    coastal_mask_file_for_var="$COASTAL_MASK_FILE"
    coastal_mask_var_for_var="$COASTAL_MASK_VAR"
    fill_baseline_gaps_for_var="$FILL_BASELINE_COASTAL_GAPS"
  fi

  DATASET_LABEL="${dataset_label}" \
  MODEL_LABEL="${model}" \
  REALIZATION_LABEL="${member}" \
  FORCING_LABEL="${scenario}" \
  VAR_MAP_SPEC="${var}:${var}" \
  BASELINE_ROOT="${BASELINE_ROOT:-${baseline_root}}" \
  BASELINE_TAG="${BASELINE_TAG}" \
  BASELINE_FILE_TEMPLATE="${BASELINE_FILE_TEMPLATE:-${baseline_file_template}}" \
  ANOMALY_ROOT="${anomaly_root}" \
  ANOMALY_FILE_TEMPLATE="${ANOMALY_FILE_TEMPLATE:-__ANOMALY_ROOT__/__SRC_VAR__/delta_windows_0p25/ipcc_esgf_${model}_${scenario}_${member}___SRC_VAR___delta___WINDOW___minus___BASELINE_TAG___grid_0p25_global.nc}" \
  OUTROOT="${OUTROOT:-/home/SB5/downscaled}" \
  ANOMALY_GRIDFILE="${ANOMALY_GRIDFILE:-${anomaly_gridfile}}" \
  COASTAL_MASK_FILE="${coastal_mask_file_for_var}" \
  COASTAL_MASK_VAR="${coastal_mask_var_for_var}" \
  FILL_BASELINE_COASTAL_GAPS="${fill_baseline_gaps_for_var}" \
  FILL_TOP_MISSING_ANOMALY="${FILL_TOP_MISSING_ANOMALY}" \
  ANOMALY_MODE="${ANOMALY_MODE}" \
  ANOMALY_MODE_SPEC="${ANOMALY_MODE_SPEC}" \
  COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD:-distance_weighted}" \
  COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER:-2.0}" \
  COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS:-4}" \
  COASTAL_FILL_REQUIRE_COMPLETE="${COASTAL_FILL_REQUIRE_COMPLETE}" \
  COASTAL_FILL_COMPLETE_FALLBACK_VALUE="${COASTAL_FILL_COMPLETE_FALLBACK_VALUE}" \
  REGRID_GRIDFILE="${REGRID_GRIDFILE:-${regrid_gridfile}}" \
  REGRID_SUFFIX="${REGRID_SUFFIX:-${regrid_suffix}}" \
  "${GENERIC_RUNNER}" "$@"
done

echo "Done."
