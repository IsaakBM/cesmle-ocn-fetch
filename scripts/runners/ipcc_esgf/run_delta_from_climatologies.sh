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
#       * ssp585 2050-2060 minus historical 2006-2014
#       * ssp585 2090-2100 minus historical 2006-2014
#   - The delta core can optionally regrid, and this runner enables regridding
#     to a common 0.25 x 0.25 degree lon/lat grid.
#   - Expected climatology layout:
#       /home/SB5/ipcc_esgf_monthly_1deg/<model>/historical/<var>/clim_windows/*.nc
#       /home/SB5/ipcc_esgf_monthly_1deg/<model>/<ssp-scenario>/<var>/clim_windows/*.nc
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/delta_from_climatologies.slurm.sh"
DISCOVERY_LIB="${SCRIPT_DIR}/../../lib/ipcc_esgf_discovery.sh"

# shellcheck source=../../lib/ipcc_esgf_discovery.sh
source "${DISCOVERY_LIB}"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS=(
  chl
  o2
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="ipcc_esgf"
ROOT="/home/SB5/ipcc_esgf_monthly_1deg"
GRIDFILE="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/grid_0p25_global.txt"
METHOD="remapdis"
BASELINE_TAG="2006-2014"
FUT2050_TAG="2050-2060"
FUT2090_TAG="2090-2100"
REGRID_SUFFIX="grid_0p25_global"
HISTORICAL_SCENARIO="${HISTORICAL_SCENARIO:-historical}"
MEMBER="${MEMBER:-auto}"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

if [[ ! -f "$GRIDFILE" ]]; then
  echo "ERROR: Grid file not found: $GRIDFILE"
  exit 1
fi

echo "Submitting IPCC/ESGF delta jobs with generic worker:"
mapfile -t FUTURE_GROUPS < <(ipcc_esgf_discover_monthly_groups "${ROOT}" "clim_windows" | awk -F '\t' '$2 ~ /^ssp[0-9][0-9][0-9]$/' | sort -u)

if (( ${#FUTURE_GROUPS[@]} == 0 )); then
  echo "ERROR: No future scenario climatology groups discovered under: ${ROOT}"
  exit 1
fi

for group in "${FUTURE_GROUPS[@]}"; do
  IFS=$'\t' read -r model scen v <<< "$group"

  if [[ ! " ${VARS[*]} " == *" ${v} "* ]]; then
    continue
  fi

  HIST_DIR="${ROOT}/${model}/${HISTORICAL_SCENARIO}/${v}/clim_windows"
  SSP_DIR="${ROOT}/${model}/${scen}/${v}/clim_windows"
  OUT_DIR="${ROOT}/${model}/${scen}/${v}/delta_windows"
  TMP_DIR="${ROOT}/${model}/${scen}/${v}/tmp_delta"
  REGRID_OUT_DIR="${ROOT}/${model}/${scen}/${v}/delta_windows_0p25"

  if [[ ! -d "$HIST_DIR" ]]; then
    echo "WARN: Historical climatology directory not found, skipping: $HIST_DIR"
    continue
  fi

  if [[ ! -d "$SSP_DIR" ]]; then
    echo "WARN: SSP585 climatology directory not found, skipping: $SSP_DIR"
    continue
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
  FUT2050_FILE="${SSP_DIR}/${DATASET_LABEL}_${model}_${scen}_${member}_${v}_clim_${FUT2050_TAG}.nc"
  FUT2090_FILE="${SSP_DIR}/${DATASET_LABEL}_${model}_${scen}_${member}_${v}_clim_${FUT2090_TAG}.nc"
  DELTA_PREFIX="${DATASET_LABEL}_${model}_${scen}_${member}_${v}"

  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "WARN: Missing baseline climatology for VAR=${v}: ${BASELINE_FILE}"
    continue
  fi

  if [[ -f "$FUT2050_FILE" ]]; then
    jid2050=$(DATASET_LABEL="${DATASET_LABEL}_${model}_${scen}_${member}" \
      VAR="$v" \
      BASELINE_FILE="$BASELINE_FILE" \
      FUTURE_FILE="$FUT2050_FILE" \
      OUT_DIR="$OUT_DIR" \
      TMP_DIR="$TMP_DIR" \
      FUTURE_TAG="$FUT2050_TAG" \
      BASELINE_TAG="$BASELINE_TAG" \
      OUT_PREFIX="${DELTA_PREFIX}" \
      REGRID_DELTA="yes" \
      GRIDFILE="$GRIDFILE" \
      METHOD="$METHOD" \
      REGRID_OUT_DIR="$REGRID_OUT_DIR" \
      REGRID_SUFFIX="$REGRID_SUFFIX" \
      sbatch --parsable \
      --job-name="delta2050_${v}" \
      "$CORE_SCRIPT")
    echo "  submitted MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v} WINDOW=${FUT2050_TAG} as jobid=${jid2050}"
  else
    echo "WARN: Missing 2050 climatology for VAR=${v}: ${FUT2050_FILE}"
  fi

  if [[ -f "$FUT2090_FILE" ]]; then
    jid2090=$(DATASET_LABEL="${DATASET_LABEL}_${model}_${scen}_${member}" \
      VAR="$v" \
      BASELINE_FILE="$BASELINE_FILE" \
      FUTURE_FILE="$FUT2090_FILE" \
      OUT_DIR="$OUT_DIR" \
      TMP_DIR="$TMP_DIR" \
      FUTURE_TAG="$FUT2090_TAG" \
      BASELINE_TAG="$BASELINE_TAG" \
      OUT_PREFIX="${DELTA_PREFIX}" \
      REGRID_DELTA="yes" \
      GRIDFILE="$GRIDFILE" \
      METHOD="$METHOD" \
      REGRID_OUT_DIR="$REGRID_OUT_DIR" \
      REGRID_SUFFIX="$REGRID_SUFFIX" \
      sbatch --parsable \
      --job-name="delta2090_${v}" \
      "$CORE_SCRIPT")
    echo "  submitted MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v} WINDOW=${FUT2090_TAG} as jobid=${jid2090}"
  else
    echo "WARN: Missing 2090 climatology for VAR=${v}: ${FUT2090_FILE}"
  fi
done

echo "Done."
