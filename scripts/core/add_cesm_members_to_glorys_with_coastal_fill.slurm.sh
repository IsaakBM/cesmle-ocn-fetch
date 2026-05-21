#!/usr/bin/env bash
# ==============================================================================
#  CESM member-to-GLORYS coastal-fill downscaling worker
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ============================================================================== 
#
#  Purpose:
#    - For one CESM source variable, loop over all regridded 0.05 degree member
#      anomaly files for 2050-2060 and 2090-2100
#    - Add each anomaly to the trusted GLORYS baseline using coastal fill
#    - Preserve the legacy CESM-to-GLORYS launch pattern:
#        one Slurm job per variable, many member files processed inside the job
#
#  Notes:
#    - This worker intentionally uses the existing generic coastal-fill core
#      worker as the per-file engine, while restoring the old coarser GLORYS
#      submission granularity.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=addcf_cesm_glorys
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=256G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/addcf_cesm_glorys_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/addcf_cesm_glorys_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
export OMP_NUM_THREADS=1
shopt -s nullglob

# ==============================================================================
# Required env vars
#   VAR                       : CESM source variable (TEMP, SALT, UVEL)
#
# Optional env vars
#   DATASET_LABEL             : default cesm_to_glorys
#   RCP85_ROOT                : default /home/SB5/rcp85
#   GLORYS_ROOT               : default /home/SB5/glorys12v1_monthly_0p05
#   OUTROOT                   : default /home/SB5/downscaled
#   MODEL_LABEL               : default cesm_f09_g16
#   FORCING_LABEL             : default rcp85
#   BASELINE_TAG              : default 2006-2014
#   OUT_SUFFIX                : default downscaled
#   MAX_JOBS                  : max concurrent member files inside this Slurm job
#                               default 2
#   REMAP_ANOMALY_TO_BASELINE : forwarded to generic worker (default no)
#   COASTAL_FILL              : forwarded to generic worker (default yes)
#   COASTAL_FILL_METHOD       : forwarded to generic worker
#                               (default: distance_weighted)
#   COASTAL_FILL_MAX_STEPS    : forwarded to generic worker (default 12)
#   COASTAL_FILL_WEIGHT_POWER : forwarded to generic worker (default 2.0)
#   COASTAL_FILL_MIN_DONORS   : forwarded to generic worker (default 4)
#   WRITE_FILLED_ANOM         : forwarded to generic worker (default no)
# ==============================================================================

REPO_DIR="${SLURM_SUBMIT_DIR:-${PWD}}"
CORE_SCRIPT="${REPO_DIR}/scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh"

DATASET_LABEL="${DATASET_LABEL:-cesm_to_glorys}"
RCP85_ROOT="${RCP85_ROOT:-/home/SB5/rcp85}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/glorys12v1_monthly_0p05}"
OUTROOT="${OUTROOT:-/home/SB5/downscaled}"
MODEL_LABEL="${MODEL_LABEL:-cesm_f09_g16}"
FORCING_LABEL="${FORCING_LABEL:-rcp85}"
BASELINE_TAG="${BASELINE_TAG:-2006-2014}"
OUT_SUFFIX="${OUT_SUFFIX:-downscaled}"
MAX_JOBS="${MAX_JOBS:-2}"

REMAP_ANOMALY_TO_BASELINE="${REMAP_ANOMALY_TO_BASELINE:-no}"
COASTAL_FILL="${COASTAL_FILL:-yes}"
COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD:-distance_weighted}"
COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS:-12}"
COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER:-2.0}"
COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS:-4}"
WRITE_FILLED_ANOM="${WRITE_FILLED_ANOM:-no}"

CESM_VAR="${VAR:-}"
FUT1_TAG="2050-2060"
FUT2_TAG="2090-2100"

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

realization_for_member_tag() {
  local member_tag="$1"

  if [[ "${member_tag}" =~ \.([0-9]{3})\.pop\. ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "${member_tag}" =~ f09_g16\.([0-9]{3})\. ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  printf 'unknown_member\n'
}

if [[ -z "${CESM_VAR}" ]]; then
  echo "ERROR: VAR is not set."
  echo "Supported values: TEMP, SALT, UVEL"
  exit 1
fi

if ! GLORYS_VAR="$(glorys_var_for_cesm_var "${CESM_VAR}")"; then
  echo "ERROR: Unsupported VAR='${CESM_VAR}'"
  echo "Supported values: TEMP, SALT, UVEL"
  exit 1
fi

BASELINE_FILE="${GLORYS_ROOT}/${GLORYS_VAR}/clim_windows/glorys12v1_${GLORYS_VAR}_clim_${BASELINE_TAG}.nc"
ANOM_DIR="${RCP85_ROOT}/${CESM_VAR}/delta_windows/member_deltas_0p05"

OUT_VAR_BASE_DIR="${OUTROOT}/${MODEL_LABEL}"
TMP_DIR="${OUT_VAR_BASE_DIR}/tmp_add_coastal_fill/${GLORYS_VAR}"

mkdir -p "${TMP_DIR}"

if [[ ! -f "${BASELINE_FILE}" ]]; then
  echo "ERROR: GLORYS baseline file not found:"
  echo "  ${BASELINE_FILE}"
  exit 1
fi

if [[ ! -d "${ANOM_DIR}" ]]; then
  echo "ERROR: Anomaly directory not found:"
  echo "  ${ANOM_DIR}"
  exit 1
fi

if [[ ! -f "${CORE_SCRIPT}" ]]; then
  echo "ERROR: Generic coastal-fill core worker not found:"
  echo "  ${CORE_SCRIPT}"
  exit 1
fi

echo "============================================================"
echo "Starting GLORYS + CESM coastal-fill downscaling"
echo "CESM VAR            : ${CESM_VAR}"
echo "GLORYS VAR          : ${GLORYS_VAR}"
echo "MODEL LABEL         : ${MODEL_LABEL:-<none>}"
echo "FORCING LABEL       : ${FORCING_LABEL:-<none>}"
echo "BASELINE FILE       : ${BASELINE_FILE}"
echo "ANOM DIR            : ${ANOM_DIR}"
echo "OUT ROOT            : ${OUT_VAR_BASE_DIR}"
echo "TMP DIR             : ${TMP_DIR}"
echo "MAX JOBS            : ${MAX_JOBS}"
echo "COASTAL FILL        : ${COASTAL_FILL}"
echo "COASTAL FILL METHOD : ${COASTAL_FILL_METHOD}"
echo "COASTAL FILL STEPS  : ${COASTAL_FILL_MAX_STEPS}"
echo "COASTAL FILL POWER  : ${COASTAL_FILL_WEIGHT_POWER}"
echo "COASTAL FILL DONORS : ${COASTAL_FILL_MIN_DONORS}"
echo "============================================================"

process_one_anomaly_file() {
  local anom_file="$1"
  local future_tag="$2"

  local anom_name member_tag realization out_dir file_tmp_dir

  anom_name="$(basename "${anom_file}")"
  member_tag="${anom_name%_delta_${future_tag}_minus_${BASELINE_TAG}_0p05.nc}"
  realization="$(realization_for_member_tag "${member_tag}")"

  case "${future_tag}" in
    "${FUT1_TAG}")
      out_dir="${OUTROOT}/${MODEL_LABEL}/${realization}/${FORCING_LABEL}/${GLORYS_VAR}/0p05/${FUT1_TAG}"
      ;;
    "${FUT2_TAG}")
      out_dir="${OUTROOT}/${MODEL_LABEL}/${realization}/${FORCING_LABEL}/${GLORYS_VAR}/0p05/${FUT2_TAG}"
      ;;
    *)
      echo "[ERROR] Unknown future tag: ${future_tag}"
      return 1
      ;;
  esac

  file_tmp_dir="${TMP_DIR}/${realization}_${future_tag}"
  mkdir -p "${out_dir}" "${file_tmp_dir}"

  echo
  echo "[START] ${anom_name}"

  DATASET_LABEL="${DATASET_LABEL}" \
    VAR="${GLORYS_VAR}" \
    BASELINE_FILE="${BASELINE_FILE}" \
    ANOMALY_FILE="${anom_file}" \
    OUT_DIR="${out_dir}" \
    TMP_DIR="${file_tmp_dir}" \
    OUT_PREFIX="${member_tag}" \
    FUTURE_TAG="${future_tag}" \
    OUT_SUFFIX="${OUT_SUFFIX}_${GLORYS_VAR}" \
    WRITE_NATIVE_OUTPUT="yes" \
    FILL_TOP_MISSING="yes" \
    WRITE_FILLED_ANOM="${WRITE_FILLED_ANOM}" \
    REMAP_ANOMALY_TO_BASELINE="${REMAP_ANOMALY_TO_BASELINE}" \
    COASTAL_FILL="${COASTAL_FILL}" \
    COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD}" \
    COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS}" \
    COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER}" \
    COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS}" \
    REGRID_OUTPUT="no" \
    bash "${CORE_SCRIPT}"

  echo "[DONE ] ${member_tag} ${future_tag} realization=${realization}"
}

process_window() {
  local future_tag="$1"
  local files=()

  files=( "${ANOM_DIR}"/*"_delta_${future_tag}_minus_${BASELINE_TAG}_0p05.nc" )

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "ERROR: No anomaly files found for ${future_tag} in:"
    echo "  ${ANOM_DIR}"
    exit 1
  fi

  echo
  echo "------------------------------------------------------------"
  echo "Processing future window: ${future_tag}"
  echo "Found ${#files[@]} member anomaly files."
  echo "------------------------------------------------------------"

  local running=0
  for f in "${files[@]}"; do
    process_one_anomaly_file "${f}" "${future_tag}" &
    ((running+=1))

    if (( running >= MAX_JOBS )); then
      wait -n
      ((running-=1))
    fi
  done

  wait
}

process_window "${FUT1_TAG}"
process_window "${FUT2_TAG}"

echo
echo "All coastal-fill downscaling completed for VAR=${CESM_VAR}"
