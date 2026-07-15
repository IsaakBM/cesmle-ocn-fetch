#!/usr/bin/env bash
# ==============================================================================
#  IPCC ESGF runner for generic delta builder from climatology files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit delta jobs for selected variable(s) using the generic delta
# builder from climatology files.
#
# Notes:
#   - This runner computes:
#       * each discovered SSP future window minus historical 2006-2014
#   - The delta core can optionally regrid. This runner enables regridding
#     to a common 0.25 x 0.25 degree lon/lat grid for ocean variables.
#   - Diagnostic variables listed in NO_REGRID_DELTA_VARS, currently siconc,
#     stop at delta_windows/ because they do not use the hindcast target grid.
#   - Expected climatology layout:
#       /home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/historical/<var>/clim_windows/*.nc
#       /home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<ssp-scenario>/<var>/clim_windows/*.nc
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/delta_from_climatologies.slurm.sh"
DISCOVERY_LIB="${SCRIPT_DIR}/../../lib/ipcc_esgf_discovery.sh"

# shellcheck source=../../lib/ipcc_esgf_discovery.sh
source "${DISCOVERY_LIB}"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS_DEFAULT=(
  thetao
  so
  ph
  o2
  chl
  uo
  vo
  zooc
  zos
  mlotst
  siconc
)
read -r -a VARS <<< "${VARS:-${VARS_DEFAULT[*]}}"
read -r -a NO_REGRID_DELTA_VARS <<< "${NO_REGRID_DELTA_VARS:-siconc}"
read -r -a MODELS <<< "${MODELS:-}"
read -r -a SCENARIOS <<< "${SCENARIOS:-}"
read -r -a WINDOWS <<< "${WINDOWS:-}"
EXCLUDE_NODES="${EXCLUDE_NODES:-}"

contains_filter_value() {
  local value="$1"
  shift

  if (( $# == 0 )); then
    return 0
  fi

  local allowed
  for allowed in "$@"; do
    if [[ "$value" == "$allowed" ]]; then
      return 0
    fi
  done

  return 1
}

make_sbatch_extra_args() {
  if [[ -n "$EXCLUDE_NODES" ]]; then
    printf '%s\n' "--exclude=${EXCLUDE_NODES}"
  fi
}

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="ipcc_esgf"
IPCC_ESGF_ROOT="${IPCC_ESGF_ROOT:-/home/SB5/ipcc_esgf}"
ROOT="${ROOT:-${IPCC_ESGF_ROOT}/monthly_1deg}"
GRIDFILE="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/grid_0p25_global.txt"
METHOD="remapdis"
BASELINE_TAG="2006-2014"
FUTURE_TAGS=(
  2030-2060
  2050-2060
  2090-2100
)
REGRID_SUFFIX="grid_0p25_global"
HISTORICAL_SCENARIO="${HISTORICAL_SCENARIO:-historical}"
MEMBER="${MEMBER:-auto}"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

should_regrid_delta() {
  local var="$1"
  local excluded

  for excluded in "${NO_REGRID_DELTA_VARS[@]}"; do
    if [[ "$var" == "$excluded" ]]; then
      return 1
    fi
  done

  return 0
}

echo "Submitting IPCC/ESGF delta jobs with generic worker:"
mapfile -t FUTURE_GROUPS < <(ipcc_esgf_discover_monthly_groups_any_layout "${ROOT}" "clim_windows" | awk -F '\t' '$3 ~ /^ssp[0-9][0-9][0-9]$/' | sort -u)

if (( ${#FUTURE_GROUPS[@]} == 0 )); then
  echo "ERROR: No future scenario climatology groups discovered under: ${ROOT}"
  exit 1
fi

for group in "${FUTURE_GROUPS[@]}"; do
  IFS=$'\t' read -r model member scen v <<< "$group"

  if [[ ! " ${VARS[*]} " == *" ${v} "* ]]; then
    continue
  fi

  if ! contains_filter_value "$model" "${MODELS[@]}"; then
    continue
  fi

  if ! contains_filter_value "$scen" "${SCENARIOS[@]}"; then
    continue
  fi

  if [[ "${MEMBER}" != "auto" && "${member}" != "${MEMBER}" ]]; then
    continue
  fi

  if ! HIST_DIR="$(ipcc_esgf_monthly_stage_dir_for_group "$ROOT" "$model" "$member" "$HISTORICAL_SCENARIO" "$v" "clim_windows")"; then
    echo "WARN: Historical climatology directory not found, skipping MODEL=${model} MEMBER=${member} VAR=${v}"
    continue
  fi

  if ! SSP_DIR="$(ipcc_esgf_monthly_stage_dir_for_group "$ROOT" "$model" "$member" "$scen" "$v" "clim_windows")"; then
    echo "WARN: SSP climatology directory not found, skipping MODEL=${model} MEMBER=${member} SCENARIO=${scen} VAR=${v}"
    continue
  fi

  VAR_DIR="$(ipcc_esgf_monthly_var_dir_for_group "$ROOT" "$model" "$member" "$scen" "$v")"
  OUT_DIR="${VAR_DIR}/delta_windows"
  TMP_DIR="${VAR_DIR}/tmp_delta"
  REGRID_OUT_DIR="${VAR_DIR}/delta_windows_0p25"
  regrid_delta="yes"
  if ! should_regrid_delta "$v"; then
    regrid_delta="no"
    REGRID_OUT_DIR=""
  elif [[ ! -f "$GRIDFILE" ]]; then
    echo "ERROR: Grid file not found: $GRIDFILE"
    exit 1
  fi

  hist_member="$(ipcc_esgf_resolve_product_member "$HIST_DIR" "$model" "$HISTORICAL_SCENARIO" "$v" "*.nc")" || {
    status=$?
    [[ "$status" -eq 2 ]] && continue
    exit "$status"
  }
  fut_member="$(ipcc_esgf_resolve_product_member "$SSP_DIR" "$model" "$scen" "$v" "*.nc")" || {
    status=$?
    [[ "$status" -eq 2 ]] && continue
    exit "$status"
  }

  if [[ "$hist_member" != "$fut_member" ]]; then
    echo "ERROR: Historical/future member mismatch for MODEL=${model} VAR=${v}: historical=${hist_member}, ${scen}=${fut_member}" >&2
    exit 1
  fi

  member="$hist_member"
  BASELINE_FILE="${HIST_DIR}/${DATASET_LABEL}_${model}_${HISTORICAL_SCENARIO}_${member}_${v}_clim_${BASELINE_TAG}.nc"
  DELTA_PREFIX="${DATASET_LABEL}_${model}_${scen}_${member}_${v}"
  mapfile -t sbatch_extra_args < <(make_sbatch_extra_args)

  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "WARN: Missing baseline climatology for VAR=${v}: ${BASELINE_FILE}"
    continue
  fi

  for future_tag in "${FUTURE_TAGS[@]}"; do
    if ! contains_filter_value "$future_tag" "${WINDOWS[@]}"; then
      continue
    fi

    future_file="${SSP_DIR}/${DATASET_LABEL}_${model}_${scen}_${member}_${v}_clim_${future_tag}.nc"
    if [[ -f "$future_file" ]]; then
      jid=$(DATASET_LABEL="${DATASET_LABEL}_${model}_${scen}_${member}" \
        VAR="$v" \
        BASELINE_FILE="$BASELINE_FILE" \
        FUTURE_FILE="$future_file" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FUTURE_TAG="$future_tag" \
        BASELINE_TAG="$BASELINE_TAG" \
        OUT_PREFIX="${DELTA_PREFIX}" \
        REGRID_DELTA="$regrid_delta" \
        GRIDFILE="$GRIDFILE" \
        METHOD="$METHOD" \
        REGRID_OUT_DIR="$REGRID_OUT_DIR" \
        REGRID_SUFFIX="$REGRID_SUFFIX" \
        sbatch --parsable \
        "${sbatch_extra_args[@]}" \
        --job-name="delta_${future_tag}_${v}" \
        "$CORE_SCRIPT")
      echo "  submitted MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v} WINDOW=${future_tag} REGRID_DELTA=${regrid_delta} as jobid=${jid}"
    else
      echo "WARN: Missing ${future_tag} climatology for VAR=${v}: ${future_file}"
    fi
  done
done

echo "Done."
