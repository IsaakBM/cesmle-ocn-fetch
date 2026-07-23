#!/usr/bin/env bash
# ==============================================================================
#  Generic runner for baseline + anomaly adder with coastal fill
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit downscaling jobs that add anomaly products to a trusted target
# baseline/current-conditions product after:
#   1. remapping the anomaly to the target baseline grid
#   2. filling anomaly gaps only within the trusted target wet mask
#   3. adding the anomaly to the target baseline
#
# This runner is intentionally source/target agnostic. The trusted target can
# be hindcast, GLORYS, or another current-conditions product as long as:
#   - BASELINE_FILE_TEMPLATE resolves to the intended target climatology file
#   - ANOMALY_FILE_TEMPLATE resolves to the anomaly file
#   - ANOMALY_GRIDFILE matches the trusted target grid
#   - optional COASTAL_MASK_FILE or COASTAL_MASK_FILE_TEMPLATE resolves to an
#     external wet-mask/coastline file when the fill domain should differ from
#     the baseline value field
#
# Variable mapping is controlled with VAR_MAP entries of the form:
#   source_var:target_var
# Example:
#   VAR_MAP=("TEMP:thetao" "SALT:so" "UVEL:uo")
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh"

RUN="${RUN:-yes}"
VAR_MAP_SPEC="${VAR_MAP_SPEC:-chl:chl o2:o2}"
read -r -a VAR_MAP <<< "${VAR_MAP_SPEC}"

WINDOWS_DEFAULT=(
  2030-2060
  2050-2060
  2090-2100
)
read -r -a WINDOWS <<< "${WINDOWS:-${WINDOWS_DEFAULT[*]}}"

DATASET_LABEL="${DATASET_LABEL:-anomaly_to_trusted_baseline}"
BASELINE_ROOT="${BASELINE_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast}"
ANOMALY_ROOT="${ANOMALY_ROOT:-/home/SB5/ipcc_esgf/monthly_1deg}"
OUTROOT="${OUTROOT:-/home/SB5/downscaled}"
BASELINE_TAG="${BASELINE_TAG:-2006-2014}"
OUT_SUFFIX="${OUT_SUFFIX:-downscaled}"
NATIVE_SUFFIX="${NATIVE_SUFFIX:-grid_0p05_global}"
MODEL_LABEL="${MODEL_LABEL:-}"
REALIZATION_LABEL="${REALIZATION_LABEL:-${MEMBER_LABEL:-}}"
FORCING_LABEL="${FORCING_LABEL:-${SCENARIO_LABEL:-}}"

# Supported tokens:
#   __BASELINE_ROOT__
#   __ANOMALY_ROOT__
#   __SRC_VAR__
#   __TGT_VAR__
#   __WINDOW__
#   __BASELINE_TAG__
#   __COASTAL_MASK_ROOT__
#   __MODEL_LABEL__
#   __REALIZATION_LABEL__
#   __FORCING_LABEL__
BASELINE_FILE_TEMPLATE="${BASELINE_FILE_TEMPLATE:-__BASELINE_ROOT__/__TGT_VAR__/clim_windows/global_ocean_biogeochemistry_hindcast___TGT_VAR___clim___BASELINE_TAG___grid_0p05_global.nc}"
ANOMALY_FILE_TEMPLATE="${ANOMALY_FILE_TEMPLATE:-__ANOMALY_ROOT__/__MODEL_LABEL__/__REALIZATION_LABEL__/__FORCING_LABEL__/__SRC_VAR__/delta_windows_0p25/ipcc_esgf___MODEL_LABEL_____FORCING_LABEL_____REALIZATION_LABEL_____SRC_VAR___delta___WINDOW___minus___BASELINE_TAG___grid_0p25_global.nc}"
COASTAL_MASK_ROOT="${COASTAL_MASK_ROOT:-}"
COASTAL_MASK_FILE="${COASTAL_MASK_FILE:-}"
COASTAL_MASK_FILE_TEMPLATE="${COASTAL_MASK_FILE_TEMPLATE:-}"
COASTAL_MASK_VAR="${COASTAL_MASK_VAR:-}"
FILL_BASELINE_COASTAL_GAPS="${FILL_BASELINE_COASTAL_GAPS:-no}"

REMAP_ANOMALY_TO_BASELINE="${REMAP_ANOMALY_TO_BASELINE:-yes}"
ANOMALY_GRIDFILE="${ANOMALY_GRIDFILE:-/home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt}"
ANOMALY_REGRID_METHOD="${ANOMALY_REGRID_METHOD:-auto}"
ANOMALY_AUTO_METHOD_DEFAULT="${ANOMALY_AUTO_METHOD_DEFAULT:-remapbil}"
ANOMALY_AUTO_METHOD_CURVILINEAR="${ANOMALY_AUTO_METHOD_CURVILINEAR:-remapdis}"
COASTAL_FILL="${COASTAL_FILL:-yes}"
COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD:-distance_weighted}"
COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS:-12}"
COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER:-2.0}"
COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS:-4}"
COASTAL_FILL_REQUIRE_COMPLETE="${COASTAL_FILL_REQUIRE_COMPLETE:-no}"
COASTAL_FILL_COMPLETE_FALLBACK_VALUE="${COASTAL_FILL_COMPLETE_FALLBACK_VALUE:-0}"
OUTPUT_BOUNDS_SPEC="${OUTPUT_BOUNDS_SPEC:-mlotst:0: siconc:0:1}"
ANOMALY_SCALE_SPEC="${ANOMALY_SCALE_SPEC:-siconc:0.01}"
ANOMALY_MODE="${ANOMALY_MODE:-additive}"
ANOMALY_MODE_SPEC="${ANOMALY_MODE_SPEC:-}"

WRITE_NATIVE_OUTPUT="${WRITE_NATIVE_OUTPUT:-yes}"
FILL_TOP_MISSING="${FILL_TOP_MISSING:-yes}"
FILL_TOP_MISSING_ANOMALY="${FILL_TOP_MISSING_ANOMALY:-no}"
WRITE_FILLED_ANOM="${WRITE_FILLED_ANOM:-no}"

REGRID_OUTPUT="${REGRID_OUTPUT:-yes}"
REGRID_METHOD="${REGRID_METHOD:-remapdis}"
REGRID_GRIDFILE="${REGRID_GRIDFILE:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25/grid_0p25_global.txt}"
REGRID_SUFFIX="${REGRID_SUFFIX:-grid_0p25_global}"

render_template() {
  local template="$1"
  local src_var="$2"
  local tgt_var="$3"
  local window="${4:-}"

  template="${template//__BASELINE_ROOT__/${BASELINE_ROOT}}"
  template="${template//__ANOMALY_ROOT__/${ANOMALY_ROOT}}"
  template="${template//__SRC_VAR__/${src_var}}"
  template="${template//__TGT_VAR__/${tgt_var}}"
  template="${template//__WINDOW__/${window}}"
  template="${template//__BASELINE_TAG__/${BASELINE_TAG}}"
  template="${template//__COASTAL_MASK_ROOT__/${COASTAL_MASK_ROOT}}"
  template="${template//__MODEL_LABEL__/${MODEL_LABEL}}"
  template="${template//__REALIZATION_LABEL__/${REALIZATION_LABEL}}"
  template="${template//__FORCING_LABEL__/${FORCING_LABEL}}"
  printf '%s\n' "$template"
}

anomaly_mode_for_var() {
  local src_var="$1"
  local tgt_var="$2"
  local item key value

  for item in ${ANOMALY_MODE_SPEC}; do
    key="${item%%=*}"
    value="${item#*=}"
    if [[ "$key" == "$src_var" || "$key" == "$tgt_var" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  printf '%s\n' "$ANOMALY_MODE"
}

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

if [[ ! -f "$ANOMALY_GRIDFILE" ]]; then
  echo "ERROR: anomaly target grid file not found: $ANOMALY_GRIDFILE"
  exit 1
fi

if [[ "$REGRID_OUTPUT" == "yes" && ! -f "$REGRID_GRIDFILE" ]]; then
  echo "ERROR: final regrid target file not found: $REGRID_GRIDFILE"
  exit 1
fi

if [[ "$RUN" != "yes" && "$RUN" != "no" ]]; then
  echo "ERROR: RUN must be yes or no"
  exit 1
fi

if [[ -n "$COASTAL_MASK_FILE" && ! -f "$COASTAL_MASK_FILE" ]]; then
  echo "ERROR: coastal mask file not found: $COASTAL_MASK_FILE"
  exit 1
fi

echo "Submitting anomaly-to-trusted-baseline downscaling jobs with coastal fill:"
echo "DATASET LABEL        : ${DATASET_LABEL}"
echo "BASELINE ROOT        : ${BASELINE_ROOT}"
echo "ANOMALY ROOT         : ${ANOMALY_ROOT}"
echo "OUT ROOT             : ${OUTROOT}"
echo "MODEL LABEL          : ${MODEL_LABEL:-<none>}"
echo "REALIZATION LABEL    : ${REALIZATION_LABEL:-<none>}"
echo "FORCING LABEL        : ${FORCING_LABEL:-<none>}"
echo "ANOMALY GRIDFILE     : ${ANOMALY_GRIDFILE}"
echo "COASTAL MASK FILE    : ${COASTAL_MASK_FILE:-<baseline finite mask>}"
echo "COASTAL MASK TEMPLATE: ${COASTAL_MASK_FILE_TEMPLATE:-<none>}"
echo "COASTAL MASK VAR     : ${COASTAL_MASK_VAR:-<auto>}"
echo "FILL BASELINE GAPS   : ${FILL_BASELINE_COASTAL_GAPS}"
echo "REQUIRE COMPLETE FILL: ${COASTAL_FILL_REQUIRE_COMPLETE}"
echo "COMPLETE FALLBACK VAL: ${COASTAL_FILL_COMPLETE_FALLBACK_VALUE}"
echo "FILL TOP ANOMALY     : ${FILL_TOP_MISSING_ANOMALY}"
echo "OUTPUT BOUNDS SPEC   : ${OUTPUT_BOUNDS_SPEC:-<none>}"
echo "ANOMALY SCALE SPEC   : ${ANOMALY_SCALE_SPEC:-<none>}"
echo "ANOMALY MODE DEFAULT : ${ANOMALY_MODE}"
echo "ANOMALY MODE SPEC    : ${ANOMALY_MODE_SPEC:-<none>}"
echo "REGRID OUTPUT        : ${REGRID_OUTPUT}"
echo "RUN                  : ${RUN}"

for spec in "${VAR_MAP[@]}"; do
  src_var="${spec%%:*}"
  tgt_var="${spec##*:}"
  anomaly_mode_for_this_var="$(anomaly_mode_for_var "$src_var" "$tgt_var")"

  BASELINE_FILE="$(render_template "${BASELINE_FILE_TEMPLATE}" "${src_var}" "${tgt_var}")"
  COASTAL_MASK_FILE_FOR_VAR="${COASTAL_MASK_FILE}"
  if [[ -n "${COASTAL_MASK_FILE_TEMPLATE}" ]]; then
    COASTAL_MASK_FILE_FOR_VAR="$(render_template "${COASTAL_MASK_FILE_TEMPLATE}" "${src_var}" "${tgt_var}")"
  fi
  ANOMALY_PARENT="$(dirname "$(render_template "${ANOMALY_FILE_TEMPLATE}" "${src_var}" "${tgt_var}" "window_stub")")"
  if [[ -n "${MODEL_LABEL}" && -n "${REALIZATION_LABEL}" && -n "${FORCING_LABEL}" ]]; then
    TMP_DIR="${OUTROOT}/${MODEL_LABEL}/${REALIZATION_LABEL}/${FORCING_LABEL}/${tgt_var}/tmp_add_coastal_fill"
  else
    TMP_DIR="${OUTROOT}/${tgt_var}/tmp_add_coastal_fill"
  fi

  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "WARN: Missing trusted baseline climatology for SRC=${src_var} TGT=${tgt_var}: ${BASELINE_FILE}"
    continue
  fi

  if [[ ! -d "$ANOMALY_PARENT" ]]; then
    echo "WARN: Anomaly directory not found, skipping SRC=${src_var} TGT=${tgt_var}: ${ANOMALY_PARENT}"
    continue
  fi

  if [[ -n "$COASTAL_MASK_FILE_FOR_VAR" && ! -f "$COASTAL_MASK_FILE_FOR_VAR" ]]; then
    echo "WARN: Coastal mask file not found, skipping SRC=${src_var} TGT=${tgt_var}: ${COASTAL_MASK_FILE_FOR_VAR}"
    continue
  fi

  for window in "${WINDOWS[@]}"; do
    ANOMALY_FILE="$(render_template "${ANOMALY_FILE_TEMPLATE}" "${src_var}" "${tgt_var}" "${window}")"
    if [[ ! -f "$ANOMALY_FILE" ]]; then
      echo "WARN: Missing anomaly for SRC=${src_var} TGT=${tgt_var} WINDOW=${window}: ${ANOMALY_FILE}"
      continue
    fi

    if [[ -n "${MODEL_LABEL}" && -n "${REALIZATION_LABEL}" && -n "${FORCING_LABEL}" ]]; then
      OUT_NATIVE_DIR="${OUTROOT}/${MODEL_LABEL}/${REALIZATION_LABEL}/${FORCING_LABEL}/${tgt_var}/0p05/${window}"
      OUT_REGRID_DIR="${OUTROOT}/${MODEL_LABEL}/${REALIZATION_LABEL}/${FORCING_LABEL}/${tgt_var}/0p25/${window}"
    else
      OUT_NATIVE_DIR="${OUTROOT}/${tgt_var}/0p05/${window}"
      OUT_REGRID_DIR="${OUTROOT}/${tgt_var}/0p25/${window}"
    fi

    if [[ "$RUN" == "yes" ]]; then
      jid=$(DATASET_LABEL="${DATASET_LABEL}" \
        VAR="$tgt_var" \
        BASELINE_FILE="$BASELINE_FILE" \
        ANOMALY_FILE="$ANOMALY_FILE" \
        OUT_DIR="$OUT_NATIVE_DIR" \
        TMP_DIR="$TMP_DIR" \
        OUT_PREFIX="${DATASET_LABEL}_${tgt_var}" \
        FUTURE_TAG="$window" \
        OUT_SUFFIX="$OUT_SUFFIX" \
        NATIVE_SUFFIX="$NATIVE_SUFFIX" \
        ANOMALY_MODE="$anomaly_mode_for_this_var" \
        WRITE_NATIVE_OUTPUT="$WRITE_NATIVE_OUTPUT" \
        FILL_TOP_MISSING="$FILL_TOP_MISSING" \
        FILL_TOP_MISSING_ANOMALY="$FILL_TOP_MISSING_ANOMALY" \
        WRITE_FILLED_ANOM="$WRITE_FILLED_ANOM" \
        REMAP_ANOMALY_TO_BASELINE="$REMAP_ANOMALY_TO_BASELINE" \
        ANOMALY_GRIDFILE="$ANOMALY_GRIDFILE" \
        ANOMALY_REGRID_METHOD="$ANOMALY_REGRID_METHOD" \
        ANOMALY_AUTO_METHOD_DEFAULT="$ANOMALY_AUTO_METHOD_DEFAULT" \
        ANOMALY_AUTO_METHOD_CURVILINEAR="$ANOMALY_AUTO_METHOD_CURVILINEAR" \
        COASTAL_FILL="$COASTAL_FILL" \
        COASTAL_FILL_METHOD="$COASTAL_FILL_METHOD" \
        COASTAL_MASK_FILE="$COASTAL_MASK_FILE_FOR_VAR" \
        COASTAL_MASK_VAR="$COASTAL_MASK_VAR" \
        FILL_BASELINE_COASTAL_GAPS="$FILL_BASELINE_COASTAL_GAPS" \
        COASTAL_FILL_MAX_STEPS="$COASTAL_FILL_MAX_STEPS" \
        COASTAL_FILL_WEIGHT_POWER="$COASTAL_FILL_WEIGHT_POWER" \
        COASTAL_FILL_MIN_DONORS="$COASTAL_FILL_MIN_DONORS" \
        COASTAL_FILL_REQUIRE_COMPLETE="$COASTAL_FILL_REQUIRE_COMPLETE" \
        COASTAL_FILL_COMPLETE_FALLBACK_VALUE="$COASTAL_FILL_COMPLETE_FALLBACK_VALUE" \
        OUTPUT_BOUNDS_SPEC="$OUTPUT_BOUNDS_SPEC" \
        ANOMALY_SCALE_SPEC="$ANOMALY_SCALE_SPEC" \
        REGRID_OUTPUT="$REGRID_OUTPUT" \
        REGRID_METHOD="$REGRID_METHOD" \
        REGRID_GRIDFILE="$REGRID_GRIDFILE" \
        REGRID_OUT_DIR="$OUT_REGRID_DIR" \
        REGRID_SUFFIX="$REGRID_SUFFIX" \
        sbatch --parsable \
        --job-name="addcf_${window}_${tgt_var}" \
        "$CORE_SCRIPT")
      echo "  submitted SRC=${src_var} TGT=${tgt_var} WINDOW=${window} ANOMALY_MODE=${anomaly_mode_for_this_var} as jobid=${jid}"
    else
      echo "  would submit SRC=${src_var} TGT=${tgt_var} WINDOW=${window} ANOMALY_MODE=${anomaly_mode_for_this_var}"
      echo "    native output: ${OUT_NATIVE_DIR}"
      if [[ "$REGRID_OUTPUT" == "yes" ]]; then
        echo "    regrid output: ${OUT_REGRID_DIR}"
      fi
    fi
  done
done

echo "Done."
