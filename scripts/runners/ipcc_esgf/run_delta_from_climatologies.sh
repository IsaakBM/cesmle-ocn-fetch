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
#       /home/SB5/ipcc_esgf_monthly_1deg/historical/<var>/clim_windows/*.nc
#       /home/SB5/ipcc_esgf_monthly_1deg/ssp585/<var>/clim_windows/*.nc
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/delta_from_climatologies.slurm.sh"

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

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

if [[ ! -f "$GRIDFILE" ]]; then
  echo "ERROR: Grid file not found: $GRIDFILE"
  exit 1
fi

find_first_match() {
  local pattern="$1"
  find ${pattern} -maxdepth 0 -type f 2>/dev/null | sort | head -n 1
}

echo "Submitting IPCC/ESGF delta jobs with generic worker:"
for v in "${VARS[@]}"; do
  HIST_DIR="${ROOT}/historical/${v}/clim_windows"
  SSP_DIR="${ROOT}/ssp585/${v}/clim_windows"
  OUT_DIR="${ROOT}/ssp585/${v}/delta_windows"
  TMP_DIR="${ROOT}/ssp585/${v}/tmp_delta"
  REGRID_OUT_DIR="${ROOT}/ssp585/${v}/delta_windows_0p25"

  if [[ ! -d "$HIST_DIR" ]]; then
    echo "WARN: Historical climatology directory not found, skipping: $HIST_DIR"
    continue
  fi

  if [[ ! -d "$SSP_DIR" ]]; then
    echo "WARN: SSP585 climatology directory not found, skipping: $SSP_DIR"
    continue
  fi

  BASELINE_FILE="$(find_first_match "${HIST_DIR}/*${v}*clim_${BASELINE_TAG}.nc")"
  FUT2050_FILE="$(find_first_match "${SSP_DIR}/*${v}*clim_${FUT2050_TAG}.nc")"
  FUT2090_FILE="$(find_first_match "${SSP_DIR}/*${v}*clim_${FUT2090_TAG}.nc")"

  if [[ -z "$BASELINE_FILE" ]]; then
    echo "WARN: Missing baseline climatology for VAR=${v}"
    continue
  fi

  if [[ -n "$FUT2050_FILE" ]]; then
    jid2050=$(DATASET_LABEL="${DATASET_LABEL}_ssp585" \
      VAR="$v" \
      BASELINE_FILE="$BASELINE_FILE" \
      FUTURE_FILE="$FUT2050_FILE" \
      OUT_DIR="$OUT_DIR" \
      TMP_DIR="$TMP_DIR" \
      FUTURE_TAG="$FUT2050_TAG" \
      BASELINE_TAG="$BASELINE_TAG" \
      OUT_PREFIX="${DATASET_LABEL}_${v}" \
      REGRID_DELTA="yes" \
      GRIDFILE="$GRIDFILE" \
      METHOD="$METHOD" \
      REGRID_OUT_DIR="$REGRID_OUT_DIR" \
      REGRID_SUFFIX="$REGRID_SUFFIX" \
      sbatch --parsable \
      --job-name="delta2050_${v}" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} WINDOW=${FUT2050_TAG} as jobid=${jid2050}"
  else
    echo "WARN: Missing 2050 climatology for VAR=${v}"
  fi

  if [[ -n "$FUT2090_FILE" ]]; then
    jid2090=$(DATASET_LABEL="${DATASET_LABEL}_ssp585" \
      VAR="$v" \
      BASELINE_FILE="$BASELINE_FILE" \
      FUTURE_FILE="$FUT2090_FILE" \
      OUT_DIR="$OUT_DIR" \
      TMP_DIR="$TMP_DIR" \
      FUTURE_TAG="$FUT2090_TAG" \
      BASELINE_TAG="$BASELINE_TAG" \
      OUT_PREFIX="${DATASET_LABEL}_${v}" \
      REGRID_DELTA="yes" \
      GRIDFILE="$GRIDFILE" \
      METHOD="$METHOD" \
      REGRID_OUT_DIR="$REGRID_OUT_DIR" \
      REGRID_SUFFIX="$REGRID_SUFFIX" \
      sbatch --parsable \
      --job-name="delta2090_${v}" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} WINDOW=${FUT2090_TAG} as jobid=${jid2090}"
  else
    echo "WARN: Missing 2090 climatology for VAR=${v}"
  fi
done

echo "Done."
