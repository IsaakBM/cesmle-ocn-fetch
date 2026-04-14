#!/usr/bin/env bash
# ==============================================================================
#  Global Ocean Biogeochemistry Hindcast runner for generic climatology window
#  builder from monthly files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit climatology window jobs for selected variable(s) using the
# generic climatology builder for monthly-file collections.
#
# Notes:
#   - This runner is intended for monthly files already harmonized to a common
#     0.25 x 0.25 degree grid and vertically interpolated to GLORYS levels.
#   - Expected input layout:
#       /home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/<var>/on_glorys/*.nc
#   - This runner computes one climatology per variable over the requested
#     monthly file window.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/climatology_window_from_monthly_files.slurm.sh"

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
  ph
  phyc
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="global_ocean_biogeochemistry_hindcast"
INROOT_BASE="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25"
WINDOW_START="200601"
WINDOW_END="201412"
EXPECTED_N=108

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting hindcast climatology window jobs with generic worker:"
for v in "${VARS[@]}"; do
  IN_DIR="${INROOT_BASE}/${v}/on_glorys"
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
    --job-name="clim_${v}" \
    "$CORE_SCRIPT")
  echo "  submitted VAR=${v} as jobid=${jid}"
done

echo "Done."
