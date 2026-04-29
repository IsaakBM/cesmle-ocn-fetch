#!/usr/bin/env bash
# ==============================================================================
#  CESM runner for generic baseline + anomaly adder
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit CESM member downscaling jobs that add CESM deltas to the GLORYS
# baseline climatology.
#
# Notes:
#   - Keeps the historical CESM-to-GLORYS mapping:
#       * TEMP -> thetao
#       * SALT -> so
#       * UVEL -> uo
#   - Uses member-level deltas already regridded to 0.05 degree.
#   - Native output is already at 0.05 degree, so no extra regrid is requested.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/add_anomaly_to_baseline.slurm.sh"

VARS=(
  TEMP
  SALT
  UVEL
)

WINDOWS=(
  2050-2060
  2090-2100
)

DATASET_LABEL="cesm_to_glorys"
RCP85_ROOT="/home/SB5/rcp85"
GLORYS_ROOT="/home/SB5/glorys12v1_monthly_0p05"
OUTROOT="/home/SB5/downscaled_rcp85"
BASELINE_TAG="2006-2014"
OUT_SUFFIX="downscaled"

glorys_var_for_cesm_var() {
  case "$1" in
    TEMP) printf 'thetao\n' ;;
    SALT) printf 'so\n' ;;
    UVEL) printf 'uo\n' ;;
    *)
      return 1
      ;;
  esac
}

member_prefix() {
  local member="$1"
  local var="$2"
  printf 'b.e11.BRCP85C5CNBDRD.f09_g16.%s.pop.h.%s.200601-210012.grid_1deg_pop_global_on_glorys' "$member" "$var"
}

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting CESM to GLORYS downscaling jobs with generic worker:"
for v in "${VARS[@]}"; do
  if ! GLORYS_VAR="$(glorys_var_for_cesm_var "$v")"; then
    echo "WARN: Unsupported CESM variable for add stage, skipping: ${v}"
    continue
  fi

  BASELINE_FILE="${GLORYS_ROOT}/${GLORYS_VAR}/clim_windows/glorys12v1_${GLORYS_VAR}_clim_${BASELINE_TAG}.nc"
  DELTA_DIR="${RCP85_ROOT}/${v}/delta_windows/member_deltas_0p05"
  TMP_DIR="${OUTROOT}/${GLORYS_VAR}/tmp_add"

  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "WARN: Baseline file not found, skipping: ${BASELINE_FILE}"
    continue
  fi

  if [[ ! -d "$DELTA_DIR" ]]; then
    echo "WARN: Delta directory not found, skipping: ${DELTA_DIR}"
    continue
  fi

  echo "Variable: ${v} -> ${GLORYS_VAR}"
  for member_num in $(seq 1 35); do
    member="$(printf '%03d' "${member_num}")"
    prefix="$(member_prefix "${member}" "${v}")"

    for window in "${WINDOWS[@]}"; do
      ANOMALY_FILE="${DELTA_DIR}/${prefix}_delta_${window}_minus_${BASELINE_TAG}_grid_0p05_global.nc"
      OUT_DIR="${OUTROOT}/${GLORYS_VAR}/${window}"

      if [[ ! -f "$ANOMALY_FILE" ]]; then
        echo "  WARN: Missing anomaly for VAR=${v} MEMBER=${member} WINDOW=${window}: ${ANOMALY_FILE}"
        continue
      fi

      jid=$(DATASET_LABEL="${DATASET_LABEL}" \
        VAR="$GLORYS_VAR" \
        BASELINE_FILE="$BASELINE_FILE" \
        ANOMALY_FILE="$ANOMALY_FILE" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        OUT_PREFIX="${prefix}" \
        FUTURE_TAG="$window" \
        OUT_SUFFIX="${OUT_SUFFIX}_${GLORYS_VAR}" \
        WRITE_NATIVE_OUTPUT="yes" \
        FILL_TOP_MISSING="yes" \
        REGRID_OUTPUT="no" \
        sbatch --parsable \
        --job-name="add_${GLORYS_VAR}_${window}_${member}" \
        "$CORE_SCRIPT")
      echo "  submitted VAR=${v} MEMBER=${member} WINDOW=${window} as jobid=${jid}"
    done
  done
done

echo "Done."
