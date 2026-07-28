#!/usr/bin/env bash
# ==============================================================================
#  Derive sea-water current speed from curated uo/vo products
#
#  current_speed = sqrt(uo^2 + vo^2)
#
#  Inputs and outputs live inside /home/SB5/ocean_downscaling_products:
#    baseline/uo/<resolution> + baseline/vo/<resolution>
#      -> baseline/current_speed/<resolution>
#    future/<model>/<member>/<scenario>/uo/<window>/<resolution>
#    future/<model>/<member>/<scenario>/vo/<window>/<resolution>
#      -> future/<model>/<member>/<scenario>/current_speed/<window>/<resolution>
# ==============================================================================

set -euo pipefail
shopt -s nullglob

PRODUCT_ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
DERIVE_SCOPE="${DERIVE_SCOPE:-all}"
SCENARIO="${SCENARIO:-auto}"
WINDOW="${WINDOW:-auto}"
RESOLUTIONS="${RESOLUTIONS:-0p05}"
MODELS="${MODELS:-auto}"
EXCLUDE_MODELS="${EXCLUDE_MODELS:-cesm_f09_g16 legacy_downscaled_rcp85 ensemble}"
OVERWRITE="${OVERWRITE:-no}"

if [[ "${OVERWRITE}" != "yes" && "${OVERWRITE}" != "no" ]]; then
  echo "ERROR: OVERWRITE must be yes or no" >&2
  exit 1
fi

if ! command -v cdo >/dev/null 2>&1; then
  echo "ERROR: Required command not found in PATH: cdo" >&2
  exit 1
fi

contains_word() {
  local needle="$1"
  shift
  local candidate

  for candidate in "$@"; do
    [[ "${candidate}" == "${needle}" ]] && return 0
  done
  return 1
}

read -r -a MODEL_LIST <<< "${MODELS}"
read -r -a EXCLUDE_MODEL_LIST <<< "${EXCLUDE_MODELS}"
read -r -a RESOLUTION_LIST <<< "${RESOLUTIONS}"

make_current_speed() {
  local u_file="$1"
  local v_file="$2"
  local out_file="$3"
  local out_dir
  local tmp_file

  if [[ ! -f "${u_file}" ]]; then
    echo "[WARN] Missing uo source: ${u_file}" >&2
    return 0
  fi
  if [[ ! -f "${v_file}" ]]; then
    echo "[WARN] Missing vo source: ${v_file}" >&2
    return 0
  fi

  out_dir="$(dirname "${out_file}")"
  mkdir -p "${out_dir}"

  if [[ -f "${out_file}" && "${OVERWRITE}" != "yes" ]]; then
    echo "[SKIP] ${out_file} exists (OVERWRITE=${OVERWRITE})"
    return 0
  fi

  tmp_file="${out_file}.tmp.$$.nc"
  rm -f "${tmp_file}"

  cdo -O -expr,'current_speed=sqrt(uo*uo+vo*vo)' -merge "${u_file}" "${v_file}" "${tmp_file}"

  if command -v ncatted >/dev/null 2>&1; then
    ncatted -O \
      -a standard_name,current_speed,o,c,"sea_water_speed" \
      -a long_name,current_speed,o,c,"Sea Water Current Speed" \
      -a units,current_speed,o,c,"m s-1" \
      -a derivation,current_speed,o,c,"sqrt(uo^2 + vo^2)" \
      -a source_uo,current_speed,o,c,"${u_file}" \
      -a source_vo,current_speed,o,c,"${v_file}" \
      "${tmp_file}"
  else
    echo "[WARN] ncatted not found; skipping current_speed metadata annotation" >&2
  fi

  mv -f "${tmp_file}" "${out_file}"
  echo "[WRITE] ${out_file}"
}

current_speed_basename() {
  local u_file="$1"
  local base

  base="$(basename "${u_file}")"
  if [[ "${base}" == *"_uo_"* ]]; then
    printf '%s\n' "${base/_uo_/_current_speed_}"
  elif [[ "${base}" == *"uo"* ]]; then
    printf '%s\n' "${base/uo/current_speed}"
  else
    printf 'current_speed_%s\n' "${base}"
  fi
}

derive_baseline() {
  local resolution u_dir v_dir u_file v_file out_file base

  for resolution in "${RESOLUTION_LIST[@]}"; do
    u_dir="${PRODUCT_ROOT}/baseline/uo/${resolution}"
    v_dir="${PRODUCT_ROOT}/baseline/vo/${resolution}"
    [[ -d "${u_dir}" ]] || continue
    [[ -d "${v_dir}" ]] || continue

    for u_file in "${u_dir}"/*.nc; do
      base="$(basename "${u_file}")"
      v_file="${v_dir}/${base/_uo_/_vo_}"
      if [[ "${v_file}" == "${v_dir}/${base}" ]]; then
        v_file="$(find "${v_dir}" -maxdepth 1 -type f -name '*.nc' | sort | head -1)"
      fi
      out_file="${PRODUCT_ROOT}/baseline/current_speed/${resolution}/$(current_speed_basename "${u_file}")"
      make_current_speed "${u_file}" "${v_file}" "${out_file}"
    done
  done
}

derive_future() {
  local u_file rel model realization scenario var window resolution rest
  local v_file out_file out_base

  while IFS= read -r u_file; do
    rel="${u_file#${PRODUCT_ROOT}/future/}"
    IFS='/' read -r model realization scenario var window resolution rest <<< "${rel}"

    [[ "${var}" == "uo" ]] || continue
    contains_word "${model}" "${EXCLUDE_MODEL_LIST[@]}" && continue
    if [[ "${MODELS}" != "auto" ]] && ! contains_word "${model}" "${MODEL_LIST[@]}"; then
      continue
    fi
    [[ "${SCENARIO}" != "auto" && "${SCENARIO}" != "${scenario}" ]] && continue
    [[ "${WINDOW}" != "auto" && "${WINDOW}" != "${window}" ]] && continue
    contains_word "${resolution}" "${RESOLUTION_LIST[@]}" || continue

    v_file="${PRODUCT_ROOT}/future/${model}/${realization}/${scenario}/vo/${window}/${resolution}/$(basename "${u_file}")"
    v_file="${v_file/_uo_/_vo_}"
    if [[ ! -f "${v_file}" ]]; then
      v_file="$(find "${PRODUCT_ROOT}/future/${model}/${realization}/${scenario}/vo/${window}/${resolution}" -maxdepth 1 -type f -name '*.nc' 2>/dev/null | sort | head -1 || true)"
    fi

    out_base="$(current_speed_basename "${u_file}")"
    out_file="${PRODUCT_ROOT}/future/${model}/${realization}/${scenario}/current_speed/${window}/${resolution}/${out_base}"
    make_current_speed "${u_file}" "${v_file}" "${out_file}"
  done < <(find "${PRODUCT_ROOT}/future" -path "*/uo/*/*/*.nc" -type f | sort)
}

echo "============================================================"
echo "Deriving current_speed products"
echo "PRODUCT ROOT   : ${PRODUCT_ROOT}"
echo "SCOPE          : ${DERIVE_SCOPE}"
echo "SCENARIO       : ${SCENARIO}"
echo "WINDOW         : ${WINDOW}"
echo "RESOLUTIONS    : ${RESOLUTIONS}"
echo "MODELS         : ${MODELS}"
echo "EXCLUDE MODELS : ${EXCLUDE_MODELS}"
echo "OVERWRITE      : ${OVERWRITE}"
echo "============================================================"

case "${DERIVE_SCOPE}" in
  all)
    derive_baseline
    derive_future
    ;;
  baseline)
    derive_baseline
    ;;
  future)
    derive_future
    ;;
  *)
    echo "ERROR: DERIVE_SCOPE must be all, baseline, or future" >&2
    exit 1
    ;;
esac

echo
echo "Done."
