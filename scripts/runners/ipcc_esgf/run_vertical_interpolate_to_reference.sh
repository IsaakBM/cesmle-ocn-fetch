#!/usr/bin/env bash
# ==============================================================================
#  IPCC ESGF runner for generic vertical interpolation to reference levels
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit vertical interpolation jobs for selected scenario(s) and
# variable(s) from the IPCC/ESGF branches using the generic vertical
# interpolation worker.
#
# Notes:
#   - This runner is intended for already-monthly time-series files already
#     harmonized to a common 1 x 1 degree horizontal grid.
#   - Source vertical units are assumed to already be in meters.
#   - Target levels are derived from a GLORYS reference file.
#   - Expected input layout:
#       /home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<scenario>/<var>/parts/*.nc
#   - Outputs are written to:
#       /home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<scenario>/<var>/on_glorys/
#   - 2D variables such as zos, mlotst, and siconc should skip this stage.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/vertical_interpolate_to_reference.slurm.sh"
DISCOVERY_LIB="${SCRIPT_DIR}/../../lib/ipcc_esgf_discovery.sh"

# shellcheck source=../../lib/ipcc_esgf_discovery.sh
source "${DISCOVERY_LIB}"

VARS_DEFAULT=(
  thetao
  so
  ph
  o2
  chl
  uo
  vo
  zooc
)
read -r -a VARS <<< "${VARS:-${VARS_DEFAULT[*]}}"
read -r -a MODELS <<< "${MODELS:-}"
read -r -a SCENARIOS <<< "${SCENARIOS:-}"
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
INROOT_BASE="${INROOT_BASE:-${IPCC_ESGF_ROOT}/monthly_1deg}"
TARGET_REF_FILE="/home/SB5/glorys12v1_monthly_0p05/thetao/parts/glorys12v1_thetao_200601.monmean.0p05.nc"
SHARED_TMP_DIR="/home/SB5/tmp"
SOURCE_ZDIM_NAME="lev"
SOURCE_UNITS_IN="m"
SOURCE_UNITS_OUT="m"
SOURCE_SCALE="1"
FILE_GLOB="*.nc"
OUT_SUFFIX="on_glorys"
MAX_JOBS=5
MEMBER="${MEMBER:-auto}"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting IPCC/ESGF vertical interpolation jobs with generic worker:"
mapfile -t DISCOVERED_GROUPS < <(ipcc_esgf_discover_monthly_groups_any_layout "${INROOT_BASE}" "parts" | sort -u)

if (( ${#DISCOVERED_GROUPS[@]} == 0 )); then
  echo "ERROR: No model/member/scenario/variable parts directories discovered under: ${INROOT_BASE}"
  exit 1
fi

for group in "${DISCOVERED_GROUPS[@]}"; do
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

  if ! IN_DIR="$(ipcc_esgf_monthly_stage_dir_for_group "$INROOT_BASE" "$model" "$member" "$scen" "$v" "parts")"; then
    echo "  WARN: Input directory not found, skipping MODEL=${model} MEMBER=${member} SCENARIO=${scen} VAR=${v}"
    continue
  fi

  VAR_DIR="$(ipcc_esgf_monthly_var_dir_for_group "$INROOT_BASE" "$model" "$member" "$scen" "$v")"
  OUT_DIR="${VAR_DIR}/on_glorys"
  TMP_DIR="${VAR_DIR}/tmp_vinterp"
  file_glob="${v}_*_${model}_${scen}_*.nc"

  member="$(ipcc_esgf_resolve_member "$IN_DIR" "$file_glob")" || {
    status=$?
    [[ "$status" -eq 2 ]] && continue
    exit "$status"
  }

  file_glob="${v}_*_${model}_${scen}_${member}_*.nc"
  job_label="${DATASET_LABEL}_${model}_${scen}_${member}_${v}"
  mapfile -t sbatch_extra_args < <(make_sbatch_extra_args)

  jid=$(DATASET_LABEL="${job_label}" \
      IN_DIR="$IN_DIR" \
      OUT_DIR="$OUT_DIR" \
      TMP_DIR="$TMP_DIR" \
      TARGET_REF_FILE="$TARGET_REF_FILE" \
      SHARED_TMP_DIR="$SHARED_TMP_DIR" \
      FILE_GLOB="$file_glob" \
      SOURCE_ZDIM_NAME="$SOURCE_ZDIM_NAME" \
      SOURCE_UNITS_IN="$SOURCE_UNITS_IN" \
      SOURCE_UNITS_OUT="$SOURCE_UNITS_OUT" \
      SOURCE_SCALE="$SOURCE_SCALE" \
      OUT_SUFFIX="$OUT_SUFFIX" \
      MAX_JOBS="$MAX_JOBS" \
      sbatch --parsable \
      "${sbatch_extra_args[@]}" \
      --job-name="vint_${scen}_${v}" \
      "$CORE_SCRIPT")
  echo "  submitted MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v} as jobid=${jid}"
done

echo "Done."
