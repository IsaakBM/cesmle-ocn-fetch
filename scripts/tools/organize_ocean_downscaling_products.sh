#!/usr/bin/env bash
set -euo pipefail

# Build a curated copy-only product tree for delivery/sharing without
# disturbing the original workflow-oriented directory structure.

ROOT="/home/SB5/ocean_downscaling_products"
BASELINE_DIR="${ROOT}/baseline"
FUTURE_DIR="${ROOT}/future"

HINDCAST_ROOT="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25"
GLORYS_ROOT="/home/SB5/glorys12v1_monthly_0p05"
DOWNSCALED_ROOT="/home/SB5/downscaled_rcp85"

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

copy_all_from_dir() {
  local src_dir="$1"
  local dest_dir="$2"

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

  cp -p "${src_dir}"/*.nc "${dest_dir}/"
  echo "[COPY] ${src_dir}/*.nc -> ${dest_dir}/"
}

copy_future_products() {
  local var="$1"
  local window="$2"

  local new_0p25="${DOWNSCALED_ROOT}/${var}/0p25/${window}"
  local new_0p05="${DOWNSCALED_ROOT}/${var}/0p05/${window}"
  local legacy_window="${DOWNSCALED_ROOT}/${var}/${window}"

  # Newer IPCC-to-hindcast layout with explicit resolutions.
  if [[ -d "${new_0p25}" || -d "${new_0p05}" ]]; then
    copy_all_from_dir "${new_0p25}" "${FUTURE_DIR}/${var}/${window}/0p25"
    copy_all_from_dir "${new_0p05}" "${FUTURE_DIR}/${var}/${window}/0p05"
    return 0
  fi

  # Older CESM-style layout with files directly inside the window folder.
  if [[ -d "${legacy_window}" ]]; then
    copy_all_from_dir "${legacy_window}" "${FUTURE_DIR}/${var}/${window}"
    return 0
  fi

  echo "[WARN] No recognized future layout for var=${var}, window=${window}" >&2
}

echo "============================================================"
echo "Building curated ocean downscaling product tree"
echo "ROOT          : ${ROOT}"
echo "BASELINE DIR  : ${BASELINE_DIR}"
echo "FUTURE DIR    : ${FUTURE_DIR}"
echo "============================================================"

mkdir -p "${BASELINE_DIR}" "${FUTURE_DIR}"

echo "[STEP1] Copying baseline climatologies"
copy_one \
  "${HINDCAST_ROOT}/chl/clim_windows/global_ocean_biogeochemistry_hindcast_chl_clim_2006-2014.nc" \
  "${BASELINE_DIR}/chl"
copy_one \
  "${HINDCAST_ROOT}/o2/clim_windows/global_ocean_biogeochemistry_hindcast_o2_clim_2006-2014.nc" \
  "${BASELINE_DIR}/o2"
copy_one \
  "${GLORYS_ROOT}/thetao/clim_windows/glorys12v1_thetao_clim_2006-2014.nc" \
  "${BASELINE_DIR}/thetao"
copy_one \
  "${GLORYS_ROOT}/so/clim_windows/glorys12v1_so_clim_2006-2014.nc" \
  "${BASELINE_DIR}/so"
copy_one \
  "${GLORYS_ROOT}/uo/clim_windows/glorys12v1_uo_clim_2006-2014.nc" \
  "${BASELINE_DIR}/uo"

echo "[STEP2] Copying future/downscaled products"
for var in chl o2 so thetao uo; do
  for window in 2050-2060 2090-2100; do
    copy_future_products "${var}" "${window}"
  done
done

echo
echo "Done."
