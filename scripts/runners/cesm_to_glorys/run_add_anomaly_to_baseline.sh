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
  printf 'b.e11.BRCP85C5CNBDRD.f09_g16.%s.pop.h.%s.200601-210012.1deg_on_glorys' "$member" "$var"
}

delta_dir_for_cesm_var() {
  case "$1" in
    SALT) printf '%s\n' "${RCP85_ROOT}/$1/delta_windows/member_deltas_0p05" ;;
    *)    printf '%s\n' "${RCP85_ROOT}/$1/delta_windows/member_deltas" ;;
  esac
}

delta_file_for_member_window() {
  local var="$1"
  local member="$2"
  local window="$3"
  local prefix
  local delta_dir

  prefix="$(member_prefix "${member}" "${var}")"
  delta_dir="$(delta_dir_for_cesm_var "${var}")"

  case "$var" in
    SALT)
      printf '%s/%s_delta_%s_minus_%s_0p05.nc\n' \
        "${delta_dir}" "${prefix}" "${window}" "${BASELINE_TAG}"
      ;;
    *)
      printf '%s/%s_delta_%s_minus_%s.nc\n' \
        "${delta_dir}" "${prefix}" "${window}" "${BASELINE_TAG}"
      ;;
  esac
}

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting CESM to GLORYS downscaling jobs with generic worker:"
for v in "${VARS[@]}"; do
  if ! GLORYS_VAR="$(glorys_var_for_cesm_var "$v")"; then
    echo "WARN: Unsupported CESM variable for add stage, skipping: ${v}"
    continue
  fi

  BASELINE_FILE="${GLORYS_ROOT}/${GLORYS_VAR}/clim_windows/glorys12v1_${GLORYS_VAR}_clim_${BASELINE_TAG}.nc"
  DELTA_DIR="$(delta_dir_for_cesm_var "${v}")"
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
      ANOMALY_FILE="$(delta_file_for_member_window "${v}" "${member}" "${window}")"
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
