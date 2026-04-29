#!/usr/bin/env bash
# ==============================================================================
#  IPCC ESGF to hindcast runner for baseline + anomaly adder with coastal fill
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit downscaling jobs that add IPCC/ESGF deltas to the trusted
# hindcast baseline after remapping anomalies onto the target baseline grid and
# filling coastal anomaly gaps on the baseline wet mask.
#
# Notes:
#   - Native addition is performed on the derived 0.05 hindcast baseline grid
#   - The anomaly is first remapped from the existing 0.25 delta product onto
#     that 0.05 target grid
#   - Coastal anomaly gaps are then filled on the target wet mask before
#     baseline + anomaly are combined
#   - This runner also requests a derived 0.25 product from the final 0.05
#     downscaled output so the existing product-tree layout can be preserved
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh"

VARS=(
  chl
  o2
)

WINDOWS=(
  2050-2060
  2090-2100
)

DATASET_LABEL="ipcc_esgf_to_hindcast"
HINDCAST_ROOT="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05"
DELTA_ROOT="/home/SB5/ipcc_esgf_monthly_1deg/ssp585"
OUTROOT="/home/SB5/downscaled_rcp85"
BASELINE_TAG="2006-2014"
OUT_SUFFIX="downscaled"

REMAP_ANOMALY_TO_BASELINE="yes"
ANOMALY_GRIDFILE="/home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt"
ANOMALY_REGRID_METHOD="auto"
ANOMALY_AUTO_METHOD_DEFAULT="remapbil"
ANOMALY_AUTO_METHOD_CURVILINEAR="remapdis"
COASTAL_FILL="yes"
COASTAL_FILL_MAX_STEPS="12"

REGRID_OUTPUT="yes"
REGRID_METHOD="remapdis"
REGRID_GRIDFILE="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/grid_0p25_global.txt"
REGRID_SUFFIX="grid_0p25_global"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

if [[ ! -f "$ANOMALY_GRIDFILE" ]]; then
  echo "ERROR: 0.05 anomaly target grid file not found: $ANOMALY_GRIDFILE"
  exit 1
fi

if [[ ! -f "$REGRID_GRIDFILE" ]]; then
  echo "ERROR: 0.25 final regrid file not found: $REGRID_GRIDFILE"
  exit 1
fi

echo "Submitting IPCC ESGF to hindcast downscaling jobs with coastal fill:"
for v in "${VARS[@]}"; do
  BASELINE_DIR="${HINDCAST_ROOT}/${v}/clim_windows"
  DELTA_025_DIR="${DELTA_ROOT}/${v}/delta_windows_0p25"
  TMP_DIR="${OUTROOT}/${v}/tmp_add_coastal_fill"
  BASELINE_FILE="${BASELINE_DIR}/global_ocean_biogeochemistry_hindcast_${v}_clim_${BASELINE_TAG}_grid_0p05_global.nc"

  if [[ ! -d "$BASELINE_DIR" ]]; then
    echo "WARN: Hindcast climatology directory not found, skipping: $BASELINE_DIR"
    continue
  fi

  if [[ ! -d "$DELTA_025_DIR" ]]; then
    echo "WARN: Delta directory not found, skipping: $DELTA_025_DIR"
    continue
  fi

  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "WARN: Missing 0.05 hindcast baseline climatology for VAR=${v}: ${BASELINE_FILE}"
    continue
  fi

  for window in "${WINDOWS[@]}"; do
    DELTA_FILE="${DELTA_025_DIR}/ipcc_esgf_ssp585_${v}_delta_${window}_minus_${BASELINE_TAG}_grid_0p25_global.nc"
    if [[ ! -f "$DELTA_FILE" ]]; then
      echo "WARN: Missing delta for VAR=${v} WINDOW=${window}: ${DELTA_FILE}"
      continue
    fi

    OUT_005_DIR="${OUTROOT}/${v}/0p05/${window}"
    OUT_025_DIR="${OUTROOT}/${v}/0p25/${window}"

    jid=$(DATASET_LABEL="${DATASET_LABEL}" \
      VAR="$v" \
      BASELINE_FILE="$BASELINE_FILE" \
      ANOMALY_FILE="$DELTA_FILE" \
      OUT_DIR="$OUT_005_DIR" \
      TMP_DIR="$TMP_DIR" \
      OUT_PREFIX="${DATASET_LABEL}_${v}" \
      FUTURE_TAG="$window" \
      OUT_SUFFIX="$OUT_SUFFIX" \
      WRITE_NATIVE_OUTPUT="yes" \
      FILL_TOP_MISSING="yes" \
      WRITE_FILLED_ANOM="no" \
      REMAP_ANOMALY_TO_BASELINE="$REMAP_ANOMALY_TO_BASELINE" \
      ANOMALY_GRIDFILE="$ANOMALY_GRIDFILE" \
      ANOMALY_REGRID_METHOD="$ANOMALY_REGRID_METHOD" \
      ANOMALY_AUTO_METHOD_DEFAULT="$ANOMALY_AUTO_METHOD_DEFAULT" \
      ANOMALY_AUTO_METHOD_CURVILINEAR="$ANOMALY_AUTO_METHOD_CURVILINEAR" \
      COASTAL_FILL="$COASTAL_FILL" \
      COASTAL_FILL_MAX_STEPS="$COASTAL_FILL_MAX_STEPS" \
      REGRID_OUTPUT="$REGRID_OUTPUT" \
      REGRID_METHOD="$REGRID_METHOD" \
      REGRID_GRIDFILE="$REGRID_GRIDFILE" \
      REGRID_OUT_DIR="$OUT_025_DIR" \
      REGRID_SUFFIX="$REGRID_SUFFIX" \
      sbatch --parsable \
      --job-name="addcf_${window}_${v}" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} WINDOW=${window} as jobid=${jid}"
  done
done

echo "Done."
