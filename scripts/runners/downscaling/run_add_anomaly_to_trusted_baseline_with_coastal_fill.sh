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
#
# Variable mapping is controlled with VAR_MAP entries of the form:
#   source_var:target_var
# Example:
#   VAR_MAP=("TEMP:thetao" "SALT:so" "UVEL:uo")
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh"

VAR_MAP_SPEC="${VAR_MAP_SPEC:-chl:chl o2:o2}"
read -r -a VAR_MAP <<< "${VAR_MAP_SPEC}"

WINDOWS=(
  2050-2060
  2090-2100
)

DATASET_LABEL="${DATASET_LABEL:-anomaly_to_trusted_baseline}"
BASELINE_ROOT="${BASELINE_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05}"
ANOMALY_ROOT="${ANOMALY_ROOT:-/home/SB5/ipcc_esgf_monthly_1deg/ssp585}"
OUTROOT="${OUTROOT:-/home/SB5/downscaled}"
BASELINE_TAG="${BASELINE_TAG:-2006-2014}"
OUT_SUFFIX="${OUT_SUFFIX:-downscaled}"
NATIVE_SUFFIX="${NATIVE_SUFFIX:-grid_0p05_global}"
MODEL_LABEL="${MODEL_LABEL:-}"
SCENARIO_LABEL="${SCENARIO_LABEL:-}"

# Supported tokens:
#   __BASELINE_ROOT__
#   __ANOMALY_ROOT__
#   __SRC_VAR__
#   __TGT_VAR__
#   __WINDOW__
#   __BASELINE_TAG__
BASELINE_FILE_TEMPLATE="${BASELINE_FILE_TEMPLATE:-__BASELINE_ROOT__/__TGT_VAR__/clim_windows/global_ocean_biogeochemistry_hindcast___TGT_VAR___clim___BASELINE_TAG___grid_0p05_global.nc}"
ANOMALY_FILE_TEMPLATE="${ANOMALY_FILE_TEMPLATE:-__ANOMALY_ROOT__/__SRC_VAR__/delta_windows_0p25/ipcc_esgf_ssp585___SRC_VAR___delta___WINDOW___minus___BASELINE_TAG___grid_0p25_global.nc}"

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

WRITE_NATIVE_OUTPUT="${WRITE_NATIVE_OUTPUT:-yes}"
FILL_TOP_MISSING="${FILL_TOP_MISSING:-yes}"
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
  printf '%s\n' "$template"
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

echo "Submitting anomaly-to-trusted-baseline downscaling jobs with coastal fill:"
echo "DATASET LABEL        : ${DATASET_LABEL}"
echo "BASELINE ROOT        : ${BASELINE_ROOT}"
echo "ANOMALY ROOT         : ${ANOMALY_ROOT}"
echo "OUT ROOT             : ${OUTROOT}"
echo "MODEL LABEL          : ${MODEL_LABEL:-<none>}"
echo "SCENARIO LABEL       : ${SCENARIO_LABEL:-<none>}"
echo "ANOMALY GRIDFILE     : ${ANOMALY_GRIDFILE}"
echo "REGRID OUTPUT        : ${REGRID_OUTPUT}"

for spec in "${VAR_MAP[@]}"; do
  src_var="${spec%%:*}"
  tgt_var="${spec##*:}"

  BASELINE_FILE="$(render_template "${BASELINE_FILE_TEMPLATE}" "${src_var}" "${tgt_var}")"
  ANOMALY_PARENT="$(dirname "$(render_template "${ANOMALY_FILE_TEMPLATE}" "${src_var}" "${tgt_var}" "window_stub")")"
  if [[ -n "${MODEL_LABEL}" && -n "${SCENARIO_LABEL}" ]]; then
    TMP_DIR="${OUTROOT}/${MODEL_LABEL}/${SCENARIO_LABEL}/${tgt_var}/tmp_add_coastal_fill"
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

  for window in "${WINDOWS[@]}"; do
    ANOMALY_FILE="$(render_template "${ANOMALY_FILE_TEMPLATE}" "${src_var}" "${tgt_var}" "${window}")"
    if [[ ! -f "$ANOMALY_FILE" ]]; then
      echo "WARN: Missing anomaly for SRC=${src_var} TGT=${tgt_var} WINDOW=${window}: ${ANOMALY_FILE}"
      continue
    fi

    if [[ -n "${MODEL_LABEL}" && -n "${SCENARIO_LABEL}" ]]; then
      OUT_NATIVE_DIR="${OUTROOT}/${MODEL_LABEL}/${SCENARIO_LABEL}/${tgt_var}/0p05/${window}"
      OUT_REGRID_DIR="${OUTROOT}/${MODEL_LABEL}/${SCENARIO_LABEL}/${tgt_var}/0p25/${window}"
    else
      OUT_NATIVE_DIR="${OUTROOT}/${tgt_var}/0p05/${window}"
      OUT_REGRID_DIR="${OUTROOT}/${tgt_var}/0p25/${window}"
    fi

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
      WRITE_NATIVE_OUTPUT="$WRITE_NATIVE_OUTPUT" \
      FILL_TOP_MISSING="$FILL_TOP_MISSING" \
      WRITE_FILLED_ANOM="$WRITE_FILLED_ANOM" \
      REMAP_ANOMALY_TO_BASELINE="$REMAP_ANOMALY_TO_BASELINE" \
      ANOMALY_GRIDFILE="$ANOMALY_GRIDFILE" \
      ANOMALY_REGRID_METHOD="$ANOMALY_REGRID_METHOD" \
      ANOMALY_AUTO_METHOD_DEFAULT="$ANOMALY_AUTO_METHOD_DEFAULT" \
      ANOMALY_AUTO_METHOD_CURVILINEAR="$ANOMALY_AUTO_METHOD_CURVILINEAR" \
      COASTAL_FILL="$COASTAL_FILL" \
      COASTAL_FILL_METHOD="$COASTAL_FILL_METHOD" \
      COASTAL_FILL_MAX_STEPS="$COASTAL_FILL_MAX_STEPS" \
      COASTAL_FILL_WEIGHT_POWER="$COASTAL_FILL_WEIGHT_POWER" \
      COASTAL_FILL_MIN_DONORS="$COASTAL_FILL_MIN_DONORS" \
      REGRID_OUTPUT="$REGRID_OUTPUT" \
      REGRID_METHOD="$REGRID_METHOD" \
      REGRID_GRIDFILE="$REGRID_GRIDFILE" \
      REGRID_OUT_DIR="$OUT_REGRID_DIR" \
      REGRID_SUFFIX="$REGRID_SUFFIX" \
      sbatch --parsable \
      --job-name="addcf_${window}_${tgt_var}" \
      "$CORE_SCRIPT")
    echo "  submitted SRC=${src_var} TGT=${tgt_var} WINDOW=${window} as jobid=${jid}"
  done
done

echo "Done."
