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
DOWNSCALED_ROOT="${DOWNSCALED_ROOT:-${IPCC_DOWNSCALED_ROOT:-/home/SB5/downscaled}}"
CESM_LEGACY_DOWNSCALED_ROOT="${CESM_LEGACY_DOWNSCALED_ROOT:-${CESM_DOWNSCALED_ROOT:-/home/SB5/downscaled_rcp85}}"
MODEL="${MODEL:-auto}"
REALIZATION="${REALIZATION:-auto}"
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

    [[ "${MODEL}" != "auto" && "${MODEL}" != "${model}" ]] && continue
    [[ "${REALIZATION}" != "auto" && "${REALIZATION}" != "${realization}" ]] && continue
    [[ "${SCENARIO}" != "auto" && "${SCENARIO}" != "${scenario}" ]] && continue

    printf '%s\t%s\t%s\t%s\n' "${candidate}" "${model}" "${realization}" "${scenario}"
    count=$((count + 1))
  done < <(find "${DOWNSCALED_ROOT}" -mindepth 4 -maxdepth 4 -type d -name "${var}" | sort)

  if (( count == 0 )); then
    echo "[WARN] No downscaled ${var} directories match MODEL=${MODEL} REALIZATION=${REALIZATION} SCENARIO=${SCENARIO}" >&2
  fi
}

copy_future_products() {
  local var="$1"
  local window="$2"
  local root model realization scenario
  local copied=0

  while IFS=$'\t' read -r root model realization scenario; do
    local new_0p25="${root}/0p25/${window}"
    local new_0p05="${root}/0p05/${window}"
    local dest_base="${FUTURE_DIR}/${model}/${realization}/${scenario}/${var}/${window}"

    if [[ -d "${new_0p25}" || -d "${new_0p05}" ]]; then
      copy_all_from_dir_parallel "${new_0p25}" "${dest_base}/0p25" "future-${model}-${realization}-${scenario}-${var}-${window}-0p25"
      copy_all_from_dir_parallel "${new_0p05}" "${dest_base}/0p05" "future-${model}-${realization}-${scenario}-${var}-${window}-0p05"
      copied=$((copied + 1))
    fi
  done < <(find_downscaled_var_roots "${var}")

  if (( copied > 0 )); then
    return 0
  fi

  local legacy_root="${CESM_LEGACY_DOWNSCALED_ROOT}/${var}"
  local legacy_window="${legacy_root}/${window}"
  if [[ -d "${legacy_window}" ]]; then
    copy_all_from_dir_parallel "${legacy_window}" "${FUTURE_DIR}/legacy_downscaled_rcp85/legacy_member/rcp85/${var}/${window}/native" "future-legacy-${var}-${window}"
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
echo "DOWN ROOT     : ${DOWNSCALED_ROOT}"
echo "CESM LEGACY   : ${CESM_LEGACY_DOWNSCALED_ROOT}"
echo "MODEL         : ${MODEL}"
echo "REALIZATION   : ${REALIZATION}"
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
