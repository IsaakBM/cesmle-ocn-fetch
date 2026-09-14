#!/usr/bin/env bash
set -euo pipefail

# Build a curated copy-only product tree for delivery/sharing without
# disturbing the original workflow-oriented directory structure.

ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
BASELINE_DIR="${ROOT}/baseline"
FUTURE_DIR="${ROOT}/future"

HINDCAST_0P25_ROOT="${HINDCAST_0P25_ROOT:-/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25}"
HINDCAST_0P05_ROOT="${HINDCAST_0P05_ROOT:-/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast}"
HINDCAST_0P05_COASTAL_FILLED_ROOT="${HINDCAST_0P05_COASTAL_FILLED_ROOT:-/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_coastal_filled}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/reanalysis/glorys12v1/monthly_0p05}"
DOWNSCALED_ROOT="${DOWNSCALED_ROOT:-${IPCC_DOWNSCALED_ROOT:-/home/SB5/downscaled}}"
CESM_LEGACY_DOWNSCALED_ROOT="${CESM_LEGACY_DOWNSCALED_ROOT:-${CESM_DOWNSCALED_ROOT:-/home/SB5/downscaled_rcp85}}"
# Production selection applies to both model discovery and legacy fallback.
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS-cesm_f09_g16 legacy_downscaled_rcp85}"
MODEL="${MODEL:-auto}"
if [[ -n "${MODELS+x}" && -n "${MODELS}" ]]; then
  MODEL="auto"
else
  MODELS="${MODEL}"
fi
REALIZATION="${REALIZATION:-auto}"
SCENARIO="${SCENARIO:-auto}"
ORGANIZE_SCOPE="${ORGANIZE_SCOPE:-all}"
VAR="${VAR:-}"
WINDOW="${WINDOW:-}"
BASELINE_VARS="${BASELINE_VARS:-chl o2 ph thetao so uo vo zos mlotst siconc}"
FUTURE_VARS="${FUTURE_VARS:-thetao so ph o2 chl uo vo zooc zos mlotst siconc}"
WINDOWS="${WINDOWS:-2030-2040 2050-2060 2090-2100}"
NPROC="${NPROC:-${SLURM_CPUS_PER_TASK:-4}}"
OVERWRITE="${OVERWRITE:-no}"
# Missing requested inputs are errors; optional exploratory inventories can opt out.
STRICT_INPUTS="${STRICT_INPUTS:-yes}"
case "${STRICT_INPUTS}" in yes|no) ;; *) echo "ERROR: STRICT_INPUTS must be yes or no" >&2; exit 1 ;; esac
missing_input() {
  echo "[MISSING] $*" >&2
  [[ "${STRICT_INPUTS}" == "no" ]]
}
USE_COASTAL_FILLED_BASELINE="${USE_COASTAL_FILLED_BASELINE:-no}"
COASTAL_FILLED_BASELINE_VARS="${COASTAL_FILLED_BASELINE_VARS:-chl o2}"

read -r -a MODEL_LIST <<< "${MODELS}"
read -r -a EXCLUDE_FUTURE_MODEL_LIST <<< "${EXCLUDE_FUTURE_MODELS}"
echo "MODELS: ${MODELS}; EXCLUDE FUTURE: ${EXCLUDE_FUTURE_MODELS:-<none>}"

contains_word() {
  local needle="$1"
  shift
  local candidate

  for candidate in "$@"; do
    [[ "${candidate}" == "${needle}" ]] && return 0
  done
  return 1
}

future_resolutions_for_var() {
  local var="$1"

  case "${var}" in
    chl|o2|ph)
      printf '%s\n' "0p05 0p25"
      ;;
    thetao|so|uo|vo|zos|mlotst|siconc)
      printf '%s\n' "0p05"
      ;;
    *)
      printf '%s\n' "0p05 0p25"
      ;;
  esac
}

copy_one() {
  local src="$1"
  local dest_dir="$2"
  local dest_file

  if [[ ! -f "${src}" ]]; then
    missing_input "Missing source file: ${src}"
    return $?
  fi

  dest_file="${dest_dir}/$(basename "${src}")"
  mkdir -p "${dest_dir}"

  if [[ -f "${dest_file}" && "${OVERWRITE}" != "yes" ]]; then
    # A partial/different copy must not masquerade as a completed artifact.
    if cmp -s "${src}" "${dest_file}"; then
      echo "[SKIP] Verified identical copy: ${dest_file}"
      return 0
    fi
    echo "ERROR: Existing destination differs: ${dest_file}; review before OVERWRITE=yes" >&2
    return 1
  fi

  # Copy to a unique file beside the destination, then promote only a full copy.
  local temporary
  temporary="$(mktemp "${dest_file}.part.XXXXXX")" || return 1
  if ! cp -p "${src}" "${temporary}" || ! cmp -s "${src}" "${temporary}"; then
    rm -f "${temporary}"
    return 1
  fi
  mv -f "${temporary}" "${dest_file}" || { rm -f "${temporary}"; return 1; }
  echo "[COPY] ${src} -> ${dest_dir}/"
}

copy_all_from_dir_parallel() {
  local src_dir="$1"
  local dest_dir="$2"
  local mode_label="${3:-copy}"

  if [[ ! -d "${src_dir}" ]]; then
    missing_input "Missing source directory: ${src_dir}"
    return $?
  fi

  mkdir -p "${dest_dir}"

  shopt -s nullglob
  local files=("${src_dir}"/*.nc)
  shopt -u nullglob

  if (( ${#files[@]} == 0 )); then
    missing_input "No NetCDF files found in: ${src_dir}"
    return $?
  fi

  # Resume per file, preserving the existing parallel copy limit.
  export -f copy_one missing_input
  export OVERWRITE STRICT_INPUTS
  printf '%s\0' "${files[@]}" \
    | xargs -0 -I{} -P "${NPROC}" bash -c 'copy_one "$1" "$2"' _ "{}" "${dest_dir}" || return 1
  echo "[COPY] ${mode_label}: ${src_dir}/*.nc -> ${dest_dir}/ (files=${#files[@]} parallel=${NPROC})"
}

find_downscaled_var_roots() {
  local var="$1"
  local model realization scenario candidate count
  count=0

  if [[ ! -d "${DOWNSCALED_ROOT}" ]]; then
    echo "[WARN] Missing downscaled root: ${DOWNSCALED_ROOT}" >&2
    return 0
  fi

  while IFS= read -r candidate; do
    model="$(basename "$(dirname "$(dirname "$(dirname "${candidate}")")")")"
    realization="$(basename "$(dirname "$(dirname "${candidate}")")")"
    scenario="$(basename "$(dirname "${candidate}")")"

    contains_word "${model}" "${EXCLUDE_FUTURE_MODEL_LIST[@]}" && continue
    [[ "${MODELS}" != "auto" ]] && ! contains_word "${model}" "${MODEL_LIST[@]}" && continue
    [[ "${REALIZATION}" != "auto" && "${REALIZATION}" != "${realization}" ]] && continue
    [[ "${SCENARIO}" != "auto" && "${SCENARIO}" != "${scenario}" ]] && continue

    printf '%s\t%s\t%s\t%s\n' "${candidate}" "${model}" "${realization}" "${scenario}"
    count=$((count + 1))
  done < <(find "${DOWNSCALED_ROOT}" -mindepth 4 -maxdepth 4 -type d -name "${var}" | sort)

  if (( count == 0 )); then
    echo "[WARN] No downscaled ${var} directories match MODELS=${MODELS} REALIZATION=${REALIZATION} SCENARIO=${SCENARIO}" >&2
  fi
}

copy_future_products() {
  local var="$1"
  local window="$2"
  local root model realization scenario
  local resolutions resolution src_dir
  local copied=0
  resolutions="$(future_resolutions_for_var "${var}")"

  while IFS=$'\t' read -r root model realization scenario; do
    local dest_base="${FUTURE_DIR}/${model}/${realization}/${scenario}/${var}/${window}"

    for resolution in ${resolutions}; do
      src_dir="${root}/${resolution}/${window}"
      copy_all_from_dir_parallel "${src_dir}" "${dest_base}/${resolution}" "future-${model}-${realization}-${scenario}-${var}-${window}-${resolution}"
    done
    copied=$((copied + 1))
  done < <(find_downscaled_var_roots "${var}")

  if (( copied > 0 )); then
    return 0
  fi

  local legacy_root="${CESM_LEGACY_DOWNSCALED_ROOT}/${var}"
  local legacy_window="${legacy_root}/${window}"
  if ! contains_word "legacy_downscaled_rcp85" "${EXCLUDE_FUTURE_MODEL_LIST[@]}" && [[ -d "${legacy_window}" ]] && { [[ "${MODELS}" == "auto" ]] || contains_word "legacy_downscaled_rcp85" "${MODEL_LIST[@]}"; }; then
    copy_all_from_dir_parallel "${legacy_window}" "${FUTURE_DIR}/legacy_downscaled_rcp85/legacy_member/rcp85/${var}/${window}/native" "future-legacy-${var}-${window}"
    return 0
  fi

  missing_input "No recognized future layout for var=${var}, window=${window}"
}

copy_baseline_product() {
  local src="$1"
  local var="$2"
  local resolution="$3"

  copy_one "${src}" "${BASELINE_DIR}/${var}/${resolution}"
}

uses_coastal_filled_baseline() {
  local var="$1"
  local candidate

  [[ "${USE_COASTAL_FILLED_BASELINE}" == "yes" ]] || return 1
  for candidate in ${COASTAL_FILLED_BASELINE_VARS}; do
    [[ "${candidate}" == "${var}" ]] && return 0
  done
  return 1
}

hindcast_0p05_baseline_file() {
  local var="$1"
  local filename="$2"
  local original="${HINDCAST_0P05_ROOT}/${var}/clim_windows/${filename}"
  local filled="${HINDCAST_0P05_COASTAL_FILLED_ROOT}/${var}/clim_windows/${filename}"

  if uses_coastal_filled_baseline "${var}"; then
    if [[ -f "${filled}" ]]; then
      printf '%s\n' "${filled}"
      return 0
    fi
    echo "[WARN] Coastal-filled baseline requested but missing; falling back to original: ${filled}" >&2
  fi

  printf '%s\n' "${original}"
}

organize_one_baseline_var() {
  local var="$1"

  case "${var}" in
    chl)
      copy_baseline_product \
        "${HINDCAST_0P25_ROOT}/chl/clim_windows/global_ocean_biogeochemistry_hindcast_chl_clim_2006-2014.nc" \
        "chl" \
        "0p25"
      copy_baseline_product \
        "$(hindcast_0p05_baseline_file chl global_ocean_biogeochemistry_hindcast_chl_clim_2006-2014_grid_0p05_global.nc)" \
        "chl" \
        "0p05"
      ;;
    o2)
      copy_baseline_product \
        "${HINDCAST_0P25_ROOT}/o2/clim_windows/global_ocean_biogeochemistry_hindcast_o2_clim_2006-2014.nc" \
        "o2" \
        "0p25"
      copy_baseline_product \
        "$(hindcast_0p05_baseline_file o2 global_ocean_biogeochemistry_hindcast_o2_clim_2006-2014_grid_0p05_global.nc)" \
        "o2" \
        "0p05"
      ;;
    ph)
      copy_baseline_product \
        "${HINDCAST_0P25_ROOT}/ph/clim_windows/global_ocean_biogeochemistry_hindcast_ph_clim_2006-2014.nc" \
        "ph" \
        "0p25"
      copy_baseline_product \
        "$(hindcast_0p05_baseline_file ph global_ocean_biogeochemistry_hindcast_ph_clim_2006-2014_grid_0p05_global.nc)" \
        "ph" \
        "0p05"
      ;;
    thetao)
      copy_baseline_product \
        "${GLORYS_ROOT}/thetao/clim_windows/glorys12v1_thetao_clim_2006-2014.nc" \
        "thetao" \
        "0p05"
      ;;
    so)
      copy_baseline_product \
        "${GLORYS_ROOT}/so/clim_windows/glorys12v1_so_clim_2006-2014.nc" \
        "so" \
        "0p05"
      ;;
    uo)
      copy_baseline_product \
        "${GLORYS_ROOT}/uo/clim_windows/glorys12v1_uo_clim_2006-2014.nc" \
        "uo" \
        "0p05"
      ;;
    vo)
      copy_baseline_product \
        "${GLORYS_ROOT}/vo/clim_windows/glorys12v1_vo_clim_2006-2014.nc" \
        "vo" \
        "0p05"
      ;;
    zos)
      copy_baseline_product \
        "${GLORYS_ROOT}/zos/clim_windows/glorys12v1_zos_clim_2006-2014.nc" \
        "zos" \
        "0p05"
      ;;
    mlotst)
      copy_baseline_product \
        "${GLORYS_ROOT}/mlotst/clim_windows/glorys12v1_mlotst_clim_2006-2014.nc" \
        "mlotst" \
        "0p05"
      ;;
    siconc)
      copy_baseline_product \
        "${GLORYS_ROOT}/siconc/clim_windows/glorys12v1_siconc_clim_2006-2014.nc" \
        "siconc" \
        "0p05"
      ;;
    *)
      echo "[WARN] Unsupported baseline variable: ${var}" >&2
      ;;
  esac
}

organize_all_baselines() {
  for var in ${BASELINE_VARS}; do
    organize_one_baseline_var "${var}"
  done
}

organize_one_future_var_window() {
  local var="$1"
  local window="$2"
  if [[ "${var}" == "zooc" ]] && [[ -z "$(find_downscaled_var_roots "${var}")" ]]; then
    echo "[SKIP] zooc is diagnostic-only: no trusted add baseline configured"
    return 0
  fi
  copy_future_products "${var}" "${window}"
}

organize_all_futures() {
  local var window
  for var in ${FUTURE_VARS}; do
    for window in ${WINDOWS}; do
      organize_one_future_var_window "${var}" "${window}"
    done
  done
}

echo "============================================================"
echo "Building curated ocean downscaling product tree"
echo "ROOT          : ${ROOT}"
echo "BASELINE DIR  : ${BASELINE_DIR}"
echo "FUTURE DIR    : ${FUTURE_DIR}"
echo "HINDCAST 0.25 : ${HINDCAST_0P25_ROOT}"
echo "HINDCAST 0.05 : ${HINDCAST_0P05_ROOT}"
echo "HINDCAST FILL : ${HINDCAST_0P05_COASTAL_FILLED_ROOT}"
echo "GLORYS 0.05   : ${GLORYS_ROOT}"
echo "DOWN ROOT     : ${DOWNSCALED_ROOT}"
echo "CESM LEGACY   : ${CESM_LEGACY_DOWNSCALED_ROOT}"
echo "MODEL         : ${MODEL}"
echo "MODELS        : ${MODELS}"
echo "REALIZATION   : ${REALIZATION}"
echo "SCENARIO      : ${SCENARIO}"
echo "SCOPE         : ${ORGANIZE_SCOPE}"
echo "VAR           : ${VAR:-<all>}"
echo "WINDOW        : ${WINDOW:-<all>}"
echo "BASELINE VARS : ${BASELINE_VARS}"
echo "FUTURE VARS   : ${FUTURE_VARS}"
echo "WINDOWS       : ${WINDOWS}"
echo "PARALLEL COPY : ${NPROC}"
echo "OVERWRITE     : ${OVERWRITE}"
echo "USE FILL BASE : ${USE_COASTAL_FILLED_BASELINE}"
echo "FILL BASE VARS: ${COASTAL_FILLED_BASELINE_VARS}"
echo "============================================================"

mkdir -p "${BASELINE_DIR}" "${FUTURE_DIR}"

case "${ORGANIZE_SCOPE}" in
  all)
    echo "[STEP1] Copying baseline climatologies"
    organize_all_baselines
    echo "[STEP2] Copying future/downscaled products"
    organize_all_futures
    ;;
  baseline)
    if [[ -z "${VAR}" ]]; then
      echo "ERROR: VAR must be set when ORGANIZE_SCOPE=baseline"
      exit 1
    fi
    echo "[STEP1] Copying baseline climatology for VAR=${VAR}"
    organize_one_baseline_var "${VAR}"
    ;;
  future)
    if [[ -z "${VAR}" || -z "${WINDOW}" ]]; then
      echo "ERROR: VAR and WINDOW must be set when ORGANIZE_SCOPE=future"
      exit 1
    fi
    echo "[STEP1] Copying future products for VAR=${VAR} WINDOW=${WINDOW}"
    organize_one_future_var_window "${VAR}" "${WINDOW}"
    ;;
  *)
    echo "ERROR: ORGANIZE_SCOPE must be all, baseline, or future"
    exit 1
    ;;
esac

echo
echo "Done."
