#!/usr/bin/env bash
# ==============================================================================
#  Derive 0.05-degree hindcast baseline climatologies from 0.25-degree products
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
# ==============================================================================

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   IN_ROOT                 : hindcast baseline root at 0.25
#                             (default: /home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25)
#   OUT_ROOT                : derived hindcast baseline root at 0.05
#                             (default: /home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05)
#   GRIDFILE                : target 0.05 grid description
#                             (default: /home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt)
#   VARS                    : space-separated variable list
#                             (default: "chl o2")
#   METHOD                  : auto | cdo remap operator
#                             (default: auto)
#   AUTO_METHOD_DEFAULT     : remap op for regular lat/lon sources
#                             (default: remapbil)
#   AUTO_METHOD_CURVILINEAR : remap op for curvilinear/unstructured sources
#                             (default: remapdis)
#   OVERWRITE               : yes | no
#                             (default: yes)
# ==============================================================================
IN_ROOT="${IN_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05}"
GRIDFILE="${GRIDFILE:-/home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt}"
VARS="${VARS:-chl o2}"
METHOD="${METHOD:-auto}"
AUTO_METHOD_DEFAULT="${AUTO_METHOD_DEFAULT:-remapbil}"
AUTO_METHOD_CURVILINEAR="${AUTO_METHOD_CURVILINEAR:-remapdis}"
OVERWRITE="${OVERWRITE:-yes}"

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ ! -f "${GRIDFILE}" ]]; then
  echo "ERROR: GRIDFILE does not exist: ${GRIDFILE}"
  exit 1
fi

if [[ "${OVERWRITE}" != "yes" && "${OVERWRITE}" != "no" ]]; then
  echo "ERROR: OVERWRITE must be yes or no"
  exit 1
fi

mkdir -p "${OUT_ROOT}"

detect_gridtype() {
  local src="$1"
  local gridtype

  gridtype="$(/usr/bin/cdo -s griddes "$src" 2>/dev/null | awk '$1 == "gridtype" {print $3; exit}')"
  if [[ -z "${gridtype}" ]]; then
    gridtype="unknown"
  fi
  printf '%s\n' "${gridtype}"
}

resolve_method() {
  local src="$1"
  local gridtype

  if [[ "${METHOD}" != "auto" ]]; then
    printf '%s\n' "${METHOD}"
    return 0
  fi

  gridtype="$(detect_gridtype "$src")"
  case "${gridtype}" in
    curvilinear|unstructured)
      printf '%s\n' "${AUTO_METHOD_CURVILINEAR}"
      ;;
    *)
      printf '%s\n' "${AUTO_METHOD_DEFAULT}"
      ;;
  esac
}

process_file() {
  local infile="$1"
  local rel_path rel_dir out_dir base stem outfile tmp_out method_to_use

  rel_path="${infile#${IN_ROOT}/}"
  rel_dir="$(dirname "${rel_path}")"
  out_dir="${OUT_ROOT}/${rel_dir}"
  base="$(basename "${infile}")"
  stem="${base%.nc}"
  outfile="${out_dir}/${stem}_grid_0p05_global.nc"
  tmp_out="${out_dir}/.${stem}_grid_0p05_global.tmp.nc"

  mkdir -p "${out_dir}"

  if [[ -f "${outfile}" && "${OVERWRITE}" == "no" ]]; then
    echo "[KEEP] ${outfile}"
    return 0
  fi

  rm -f "${tmp_out}" "${outfile}"

  method_to_use="$(resolve_method "${infile}")"
  echo "[INFO ] ${rel_path} remap method resolved to: ${method_to_use}"

  /usr/bin/cdo -L -O -P 1 "${method_to_use},${GRIDFILE}" "${infile}" "${tmp_out}"
  mv -f "${tmp_out}" "${outfile}"
  echo "[DONE ] ${outfile}"
}

echo "============================================================"
echo "Deriving hindcast baseline climatologies at 0.05 degree"
echo "IN ROOT                : ${IN_ROOT}"
echo "OUT ROOT               : ${OUT_ROOT}"
echo "GRIDFILE               : ${GRIDFILE}"
echo "METHOD                 : ${METHOD}"
if [[ "${METHOD}" == "auto" ]]; then
  echo "AUTO regular           : ${AUTO_METHOD_DEFAULT}"
  echo "AUTO curvilinear       : ${AUTO_METHOD_CURVILINEAR}"
fi
echo "VARS                   : ${VARS}"
echo "OVERWRITE              : ${OVERWRITE}"
echo "============================================================"

for var in ${VARS}; do
  src_dir="${IN_ROOT}/${var}/clim_windows"
  if [[ ! -d "${src_dir}" ]]; then
    echo "[WARN] Missing climatology directory for var=${var}: ${src_dir}"
    continue
  fi

  mapfile -t files < <(find "${src_dir}" -maxdepth 1 -type f -name "*.nc" | sort)
  if (( ${#files[@]} == 0 )); then
    echo "[WARN] No climatology NetCDF files found for var=${var}: ${src_dir}"
    continue
  fi

  echo
  echo "[VAR  ] ${var}"
  for infile in "${files[@]}"; do
    process_file "${infile}"
  done
done

echo
echo "Finished deriving hindcast baseline climatologies at 0.05 degree."
