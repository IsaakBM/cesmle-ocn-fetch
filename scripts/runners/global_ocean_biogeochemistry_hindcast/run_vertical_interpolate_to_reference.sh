#!/usr/bin/env bash
# ==============================================================================
#  Global Ocean Biogeochemistry Hindcast runner for generic vertical
#  interpolation to reference levels
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit vertical interpolation jobs for selected variable(s) using the
# generic vertical interpolation worker.
#
# Notes:
#   - This runner is intended for hindcast monthly files already harmonized to a
#     common horizontal grid.
#   - Source vertical units are assumed to already be in meters.
#   - Target levels are derived from a GLORYS reference file.
#   - Expected input layout:
#       /home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/<var>/parts/*.nc
#   - Outputs are written to:
#       /home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/<var>/on_glorys/
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/vertical_interpolate_to_reference.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS=(
  chl
  no3
  po4
  si
  o2
  nppv
  fe
  spco2
  ph
  phyc
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="global_ocean_biogeochemistry_hindcast"
INROOT_BASE="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25"
TARGET_REF_FILE="/home/SB5/glorys12v1_monthly_0p05/thetao/parts/glorys12v1_thetao_200601.monmean.0p05.nc"
SHARED_TMP_DIR="/home/SB5/tmp"
SOURCE_ZDIM_NAME="depth_below_sea"
SOURCE_UNITS_IN="m"
SOURCE_UNITS_OUT="m"
SOURCE_SCALE="1"
FILE_GLOB="*.nc"
OUT_SUFFIX="on_glorys"
MAX_JOBS=5

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting hindcast vertical interpolation jobs with generic worker:"
for v in "${VARS[@]}"; do
  IN_DIR="${INROOT_BASE}/${v}/parts"
  OUT_DIR="${INROOT_BASE}/${v}/on_glorys"
  TMP_DIR="${INROOT_BASE}/${v}/tmp_vinterp"

  if [[ ! -d "$IN_DIR" ]]; then
    echo "WARN: Input directory not found, skipping: $IN_DIR"
    continue
  fi

  jid=$(DATASET_LABEL="${DATASET_LABEL}_${v}" \
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
    --job-name="vint_${v}" \
    "$CORE_SCRIPT")
  echo "  submitted VAR=${v} as jobid=${jid}"
done

echo "Done."
