#!/usr/bin/env bash
# ==============================================================================
#  CESM runner for generic delta builder from climatology files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit CESM member-level delta jobs using exact climatology filenames.
#
# Notes:
#   - Computes:
#       * 2050-2060 minus 2006-2014
#       * 2090-2100 minus 2006-2014
#   - Regrids each member delta to 0.05 degree using remapbil to preserve the
#     historical CESM-to-GLORYS workflow behavior.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/delta_from_climatologies.slurm.sh"

VARS=(
  TEMP
  SALT
  O2
  UVEL
)

DATASET_LABEL="cesm_rcp85"
ROOT="/home/SB5/rcp85"
GRIDFILE="/home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt"
METHOD="remapbil"
BASELINE_TAG="2006-2014"
FUT2050_TAG="2050-2060"
FUT2090_TAG="2090-2100"
REGRID_SUFFIX="grid_0p05_global"

member_prefix() {
  local member="$1"
  local var="$2"
  printf 'b.e11.BRCP85C5CNBDRD.f09_g16.%s.pop.h.%s.200601-210012.grid_1deg_pop_global_on_glorys' "$member" "$var"
}

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

if [[ ! -f "$GRIDFILE" ]]; then
  echo "ERROR: Grid file not found: $GRIDFILE"
  exit 1
fi

echo "Submitting CESM delta jobs with generic worker:"
for v in "${VARS[@]}"; do
  IN_DIR="${ROOT}/${v}/clim_windows"
  OUT_DIR="${ROOT}/${v}/delta_windows/member_deltas"
  TMP_DIR="${ROOT}/${v}/tmp_delta"
  REGRID_OUT_DIR="${ROOT}/${v}/delta_windows/member_deltas_0p05"

  if [[ ! -d "$IN_DIR" ]]; then
    echo "WARN: Climatology directory not found, skipping: $IN_DIR"
    continue
  fi

  echo "Variable: ${v}"
  for member_num in $(seq 1 35); do
    member="$(printf '%03d' "${member_num}")"
    prefix="$(member_prefix "${member}" "${v}")"
    BASELINE_FILE="${IN_DIR}/${prefix}_clim_${BASELINE_TAG}.nc"
    FUT2050_FILE="${IN_DIR}/${prefix}_clim_${FUT2050_TAG}.nc"
    FUT2090_FILE="${IN_DIR}/${prefix}_clim_${FUT2090_TAG}.nc"

    if [[ ! -f "$BASELINE_FILE" ]]; then
      echo "  WARN: Missing baseline climatology for VAR=${v} MEMBER=${member}: ${BASELINE_FILE}"
      continue
    fi

    if [[ -f "$FUT2050_FILE" ]]; then
      jid2050=$(DATASET_LABEL="$DATASET_LABEL" \
        VAR="$v" \
        BASELINE_FILE="$BASELINE_FILE" \
        FUTURE_FILE="$FUT2050_FILE" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FUTURE_TAG="$FUT2050_TAG" \
        BASELINE_TAG="$BASELINE_TAG" \
        OUT_PREFIX="$prefix" \
        REGRID_DELTA="yes" \
        GRIDFILE="$GRIDFILE" \
        METHOD="$METHOD" \
        REGRID_OUT_DIR="$REGRID_OUT_DIR" \
        REGRID_SUFFIX="$REGRID_SUFFIX" \
        sbatch --parsable \
        --job-name="delta2050_${v}_${member}" \
        "$CORE_SCRIPT")
      echo "  submitted VAR=${v} MEMBER=${member} WINDOW=${FUT2050_TAG} as jobid=${jid2050}"
    else
      echo "  WARN: Missing 2050 climatology for VAR=${v} MEMBER=${member}: ${FUT2050_FILE}"
    fi

    if [[ -f "$FUT2090_FILE" ]]; then
      jid2090=$(DATASET_LABEL="$DATASET_LABEL" \
        VAR="$v" \
        BASELINE_FILE="$BASELINE_FILE" \
        FUTURE_FILE="$FUT2090_FILE" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FUTURE_TAG="$FUT2090_TAG" \
        BASELINE_TAG="$BASELINE_TAG" \
        OUT_PREFIX="$prefix" \
        REGRID_DELTA="yes" \
        GRIDFILE="$GRIDFILE" \
        METHOD="$METHOD" \
        REGRID_OUT_DIR="$REGRID_OUT_DIR" \
        REGRID_SUFFIX="$REGRID_SUFFIX" \
        sbatch --parsable \
        --job-name="delta2090_${v}_${member}" \
        "$CORE_SCRIPT")
      echo "  submitted VAR=${v} MEMBER=${member} WINDOW=${FUT2090_TAG} as jobid=${jid2090}"
    else
      echo "  WARN: Missing 2090 climatology for VAR=${v} MEMBER=${member}: ${FUT2090_FILE}"
    fi
  done
done

echo "Done."
