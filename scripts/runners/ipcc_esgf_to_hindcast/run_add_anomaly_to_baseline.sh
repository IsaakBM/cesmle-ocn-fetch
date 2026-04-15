#!/usr/bin/env bash
# ==============================================================================
#  IPCC ESGF to hindcast runner for generic baseline + anomaly adder
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit downscaling jobs that add IPCC/ESGF deltas to the hindcast
# baseline climatology.
#
# Notes:
#   - Native addition is performed at 0.25 x 0.25
#   - The generic worker dynamically fills missing top anomaly layers using the
#     first deeper layer with valid values
#   - This runner also requests a 0.05 degree remapped product with remapdis
#   - Output layout follows the downscaled_rcp85 pattern, grouped by variable,
#     resolution, and future window
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/add_anomaly_to_baseline.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here
# ------------------------------------------------------------------------------
VARS=(
  chl
  o2
)

WINDOWS=(
  2050-2060
  2090-2100
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="ipcc_esgf_to_hindcast"
HINDCAST_ROOT="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25"
DELTA_ROOT="/home/SB5/ipcc_esgf_monthly_1deg/ssp585"
OUTROOT="/home/SB5/downscaled_rcp85"
BASELINE_TAG="2006-2014"
OUT_SUFFIX="downscaled"

REGRID_OUTPUT="yes"
REGRID_METHOD="remapdis"
REGRID_GRIDFILE="/home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt"
REGRID_SUFFIX="grid_0p05_global"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

if [[ ! -f "$REGRID_GRIDFILE" ]]; then
  echo "ERROR: 0.05 grid file not found: $REGRID_GRIDFILE"
  exit 1
fi

find_first_match() {
  local pattern="$1"
  find ${pattern} -maxdepth 0 -type f 2>/dev/null | sort | head -n 1
}

echo "Submitting IPCC ESGF to hindcast downscaling jobs with generic worker:"
for v in "${VARS[@]}"; do
  BASELINE_DIR="${HINDCAST_ROOT}/${v}/clim_windows"
  DELTA_025_DIR="${DELTA_ROOT}/${v}/delta_windows_0p25"
  TMP_DIR="${OUTROOT}/${v}/tmp_add"

  if [[ ! -d "$BASELINE_DIR" ]]; then
    echo "WARN: Hindcast climatology directory not found, skipping: $BASELINE_DIR"
    continue
  fi

  if [[ ! -d "$DELTA_025_DIR" ]]; then
    echo "WARN: Delta directory not found, skipping: $DELTA_025_DIR"
    continue
  fi

  BASELINE_FILE="$(find_first_match "${BASELINE_DIR}/*${v}*clim_${BASELINE_TAG}.nc")"
  if [[ -z "$BASELINE_FILE" ]]; then
    echo "WARN: Missing hindcast baseline climatology for VAR=${v}"
    continue
  fi

  for window in "${WINDOWS[@]}"; do
    DELTA_FILE="$(find_first_match "${DELTA_025_DIR}/*${v}*delta_${window}_minus_${BASELINE_TAG}*grid_0p25_global.nc")"
    if [[ -z "$DELTA_FILE" ]]; then
      echo "WARN: Missing delta for VAR=${v} WINDOW=${window}"
      continue
    fi

    OUT_025_DIR="${OUTROOT}/${v}/0p25/${window}"
    OUT_005_DIR="${OUTROOT}/${v}/0p05/${window}"

    jid=$(DATASET_LABEL="${DATASET_LABEL}" \
      VAR="$v" \
      BASELINE_FILE="$BASELINE_FILE" \
      ANOMALY_FILE="$DELTA_FILE" \
      OUT_DIR="$OUT_025_DIR" \
      TMP_DIR="$TMP_DIR" \
      OUT_PREFIX="${DATASET_LABEL}_${v}" \
      FUTURE_TAG="$window" \
      OUT_SUFFIX="$OUT_SUFFIX" \
      WRITE_NATIVE_OUTPUT="yes" \
      FILL_TOP_MISSING="yes" \
      REGRID_OUTPUT="$REGRID_OUTPUT" \
      REGRID_METHOD="$REGRID_METHOD" \
      REGRID_GRIDFILE="$REGRID_GRIDFILE" \
      REGRID_OUT_DIR="$OUT_005_DIR" \
      REGRID_SUFFIX="$REGRID_SUFFIX" \
      sbatch --parsable \
      --job-name="add_${window}_${v}" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} WINDOW=${window} as jobid=${jid}"
  done
done

echo "Done."
