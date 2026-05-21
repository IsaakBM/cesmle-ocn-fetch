#!/usr/bin/env bash
set -euo pipefail

# Build a curated copy-only product tree for delivery/sharing without
# disturbing the original workflow-oriented directory structure.

ROOT="/home/SB5/ocean_downscaling_products"
BASELINE_DIR="${ROOT}/baseline"
FUTURE_DIR="${ROOT}/future"

HINDCAST_0P25_ROOT="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25"
HINDCAST_0P05_ROOT="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05"
GLORYS_ROOT="/home/SB5/glorys12v1_monthly_0p05"
IPCC_DOWNSCALED_ROOT="${IPCC_DOWNSCALED_ROOT:-/home/SB5/downscaled}"
CESM_DOWNSCALED_ROOT="${CESM_DOWNSCALED_ROOT:-/home/SB5/downscaled_rcp85}"
MODEL="${MODEL:-auto}"
SCENARIO="${SCENARIO:-auto}"
ORGANIZE_SCOPE="${ORGANIZE_SCOPE:-all}"
VAR="${VAR:-}"
WINDOW="${WINDOW:-}"
NPROC="${NPROC:-${SLURM_CPUS_PER_TASK:-4}}"

copy_one() {
  local src="$1"
  local dest_dir="$2"

  if [[ ! -f "${src}" ]]; then
    echo "[WARN] Missing source file: ${src}" >&2
    return 0
  fi

  mkdir -p "${dest_dir}"
  cp -p "${src}" "${dest_dir}/"
  echo "[COPY] ${src} -> ${dest_dir}/"
}

copy_all_from_dir_parallel() {
  local src_dir="$1"
  local dest_dir="$2"
  local mode_label="${3:-copy}"

  if [[ ! -d "${src_dir}" ]]; then
    echo "[WARN] Missing source directory: ${src_dir}" >&2
    return 0
  fi

  mkdir -p "${dest_dir}"
  shopt -s nullglob
  local files=("${src_dir}"/*.nc)
  shopt -u nullglob

  if (( ${#files[@]} == 0 )); then
    echo "[WARN] No NetCDF files found in: ${src_dir}" >&2
    return 0
  fi

  printf '%s\0' "${files[@]}" \
    | xargs -0 -I{} -P "${NPROC}" cp -p "{}" "${dest_dir}/"
  echo "[COPY] ${mode_label}: ${src_dir}/*.nc -> ${dest_dir}/ (files=${#files[@]} parallel=${NPROC})"
}

is_ipcc_var() {
  local var="$1"
  [[ "$var" == "chl" || "$var" == "o2" ]]
}

resolve_single_child_dir() {
  local parent="$1"
  local label="$2"
  local requested="$3"
  local children=()

  if [[ ! -d "$parent" ]]; then
    echo "[WARN] Missing ${label} parent directory: ${parent}" >&2
    return 2
  fi

  if [[ "$requested" != "auto" ]]; then
    if [[ -d "${parent}/${requested}" ]]; then
      printf '%s\n' "$requested"
      return 0
    fi
    echo "ERROR: Requested ${label} not found under ${parent}: ${requested}" >&2
    return 1
  fi

  mapfile -t children < <(find "$parent" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
  case "${#children[@]}" in
    0)
      echo "[WARN] No ${label} directories found under: ${parent}" >&2
      return 2
      ;;
    1)
      printf '%s\n' "${children[0]}"
      return 0
      ;;
    *)
      echo "ERROR: Multiple ${label} directories found under ${parent}: ${children[*]}" >&2
      echo "       Set ${label^^}=<value> to continue." >&2
      return 1
      ;;
  esac
}

resolve_ipcc_downscaled_var_root() {
  local var="$1"
  local model scenario

  model="$(resolve_single_child_dir "${IPCC_DOWNSCALED_ROOT}" "model" "${MODEL}")" || return $?
  scenario="$(resolve_single_child_dir "${IPCC_DOWNSCALED_ROOT}/${model}" "scenario" "${SCENARIO}")" || return $?

  printf '%s/%s/%s/%s\n' "${IPCC_DOWNSCALED_ROOT}" "${model}" "${scenario}" "${var}"
}

copy_future_products() {
  local var="$1"
  local window="$2"
  local root

  if is_ipcc_var "$var"; then
    root="$(resolve_ipcc_downscaled_var_root "$var")" || {
      status=$?
      [[ "$status" -eq 2 ]] && return 0
      exit "$status"
    }
  else
    root="${CESM_DOWNSCALED_ROOT}/${var}"
  fi

  local new_0p25="${root}/0p25/${window}"
  local new_0p05="${root}/0p05/${window}"
  local legacy_window="${root}/${window}"

  # Newer IPCC-to-hindcast layout with explicit resolutions.
  if [[ -d "${new_0p25}" || -d "${new_0p05}" ]]; then
    copy_all_from_dir_parallel "${new_0p25}" "${FUTURE_DIR}/${var}/${window}/0p25" "future-${var}-${window}-0p25"
    copy_all_from_dir_parallel "${new_0p05}" "${FUTURE_DIR}/${var}/${window}/0p05" "future-${var}-${window}-0p05"
    return 0
  fi

  # Older CESM-style layout with files directly inside the window folder.
  if [[ -d "${legacy_window}" ]]; then
    copy_all_from_dir_parallel "${legacy_window}" "${FUTURE_DIR}/${var}/${window}" "future-${var}-${window}"
    return 0
  fi

  echo "[WARN] No recognized future layout for var=${var}, window=${window}" >&2
}

copy_baseline_product() {
  local src="$1"
  local var="$2"
  local resolution="$3"

  copy_one "${src}" "${BASELINE_DIR}/${var}/${resolution}"
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
        "${HINDCAST_0P05_ROOT}/chl/clim_windows/global_ocean_biogeochemistry_hindcast_chl_clim_2006-2014_grid_0p05_global.nc" \
        "chl" \
        "0p05"
      ;;
    o2)
      copy_baseline_product \
        "${HINDCAST_0P25_ROOT}/o2/clim_windows/global_ocean_biogeochemistry_hindcast_o2_clim_2006-2014.nc" \
        "o2" \
        "0p25"
      copy_baseline_product \
        "${HINDCAST_0P05_ROOT}/o2/clim_windows/global_ocean_biogeochemistry_hindcast_o2_clim_2006-2014_grid_0p05_global.nc" \
        "o2" \
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
    *)
      echo "[WARN] Unsupported baseline variable: ${var}" >&2
      ;;
  esac
}

organize_all_baselines() {
  for var in chl o2 thetao so uo; do
    organize_one_baseline_var "${var}"
  done
}

organize_one_future_var_window() {
  local var="$1"
  local window="$2"
  copy_future_products "${var}" "${window}"
}

organize_all_futures() {
  local var window
  for var in chl o2 so thetao uo; do
    for window in 2050-2060 2090-2100; do
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
echo "GLORYS 0.05   : ${GLORYS_ROOT}"
echo "IPCC DOWN     : ${IPCC_DOWNSCALED_ROOT}"
echo "CESM DOWN     : ${CESM_DOWNSCALED_ROOT}"
echo "MODEL         : ${MODEL}"
echo "SCENARIO      : ${SCENARIO}"
echo "SCOPE         : ${ORGANIZE_SCOPE}"
echo "VAR           : ${VAR:-<all>}"
echo "WINDOW        : ${WINDOW:-<all>}"
echo "PARALLEL COPY : ${NPROC}"
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
