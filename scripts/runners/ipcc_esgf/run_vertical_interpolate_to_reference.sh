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
#       /home/SB5/ipcc_esgf_monthly_1deg/<scenario>/<var>/parts/*.nc
#   - Outputs are written to:
#       /home/SB5/ipcc_esgf_monthly_1deg/<scenario>/<var>/on_glorys/
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/vertical_interpolate_to_reference.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
SCENARIOS=(
  historical
  ssp585
)

VARS=(
  chl
  o2
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="ipcc_esgf"
INROOT_BASE="/home/SB5/ipcc_esgf_monthly_1deg"
TARGET_REF_FILE="/home/SB5/glorys12v1_monthly_0p05/thetao/parts/glorys12v1_thetao_200601.monmean.0p05.nc"
SHARED_TMP_DIR="/home/SB5/tmp"
SOURCE_ZDIM_NAME="lev"
SOURCE_UNITS_IN="m"
SOURCE_UNITS_OUT="m"
SOURCE_SCALE="1"
FILE_GLOB="*.nc"
OUT_SUFFIX="on_glorys"
MAX_JOBS=5

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting IPCC/ESGF vertical interpolation jobs with generic worker:"
for scen in "${SCENARIOS[@]}"; do
  echo "Scenario: $scen"
  for v in "${VARS[@]}"; do
    IN_DIR="${INROOT_BASE}/${scen}/${v}/parts"
    OUT_DIR="${INROOT_BASE}/${scen}/${v}/on_glorys"
    TMP_DIR="${INROOT_BASE}/${scen}/${v}/tmp_vinterp"

    if [[ ! -d "$IN_DIR" ]]; then
      echo "  WARN: Input directory not found, skipping: $IN_DIR"
      continue
    fi

    jid=$(DATASET_LABEL="${DATASET_LABEL}_${scen}_${v}" \
      IN_DIR="$IN_DIR" \
      OUT_DIR="$OUT_DIR" \
      TMP_DIR="$TMP_DIR" \
      TARGET_REF_FILE="$TARGET_REF_FILE" \
      SHARED_TMP_DIR="$SHARED_TMP_DIR" \
      FILE_GLOB="$FILE_GLOB" \
      SOURCE_ZDIM_NAME="$SOURCE_ZDIM_NAME" \
      SOURCE_UNITS_IN="$SOURCE_UNITS_IN" \
      SOURCE_UNITS_OUT="$SOURCE_UNITS_OUT" \
      SOURCE_SCALE="$SOURCE_SCALE" \
      OUT_SUFFIX="$OUT_SUFFIX" \
      MAX_JOBS="$MAX_JOBS" \
      sbatch --parsable \
      --job-name="vint_${scen}_${v}" \
      "$CORE_SCRIPT")
    echo "  submitted SCENARIO=${scen} VAR=${v} as jobid=${jid}"
  done
done

echo "Done."
