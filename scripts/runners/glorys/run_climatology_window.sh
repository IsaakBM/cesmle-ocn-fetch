#!/usr/bin/env bash
# ==============================================================================
#  GLORYS12v1 runner for generic climatology window builder from monthly files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit GLORYS baseline climatology jobs for selected variable(s) using
# the generic climatology builder for monthly-file collections.
#
# Notes:
#   - This runner is intended for monthly GLORYS12v1 files already harmonized to
#     a 0.05 x 0.05 degree grid.
#   - Expected input layout:
#       /home/SB5/glorys12v1_monthly_0p05/<var>/parts/*.nc
#   - This runner computes one climatology per variable over the 2006-2014
#     monthly baseline window.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/climatology_window_from_monthly_files.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS=(
  bottomT
  mlotst
  so
  thetao
  uo
  vo
  zos
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="glorys12v1"
INROOT_BASE="/home/SB5/glorys12v1_monthly_0p05"
WINDOW_START="200601"
WINDOW_END="201412"
EXPECTED_N=108

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting GLORYS climatology window jobs with generic worker:"
for v in "${VARS[@]}"; do
  IN_DIR="${INROOT_BASE}/${v}/parts"
  OUT_DIR="${INROOT_BASE}/${v}/clim_windows"
  TMP_DIR="${INROOT_BASE}/${v}/tmp_clim"

  if [[ ! -d "$IN_DIR" ]]; then
    echo "WARN: Input directory not found, skipping: $IN_DIR"
    continue
  fi

  jid=$(DATASET_LABEL="$DATASET_LABEL" \
    VAR="$v" \
    IN_DIR="$IN_DIR" \
    OUT_DIR="$OUT_DIR" \
    TMP_DIR="$TMP_DIR" \
    FILE_GLOB="*.nc" \
    WINDOW_START="$WINDOW_START" \
    WINDOW_END="$WINDOW_END" \
    EXPECTED_N="$EXPECTED_N" \
    OUT_PREFIX="${DATASET_LABEL}_${v}" \
    sbatch --parsable \
    --job-name="gclim_${v}" \
    "$CORE_SCRIPT")
  echo "  submitted VAR=${v} as jobid=${jid}"
done

echo "Done."
