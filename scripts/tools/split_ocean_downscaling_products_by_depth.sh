#!/usr/bin/env bash
# ==============================================================================
#  Curated ocean downscaling product splitter by depth
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read curated NetCDF products from /home/SB5/ocean_downscaling_products
#    - Mirror the same baseline/future structure into a by-depth tree
#    - Split each 3D NetCDF file into one 2D NetCDF file per depth layer
#    - Include depth in the filename using a safe token such as 0p49m
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=split_bydepth
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH -t 1-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/split_bydepth_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/split_bydepth_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   IN_ROOT       : curated input root (default: /home/SB5/ocean_downscaling_products)
#   OUT_ROOT      : curated by-depth output root
#                   (default: /home/SB5/ocean_downscaling_products_bydepth)
#   TMP_DIR       : temp / bookkeeping directory
#                   (default: <OUT_ROOT>/tmp_split_bydepth)
#   MIN_DECIMALS  : minimum decimals in depth token (default: 2)
#   INTEGER_WIDTH : zero-padded width for the integer part of depth tokens
#                   (default: 4)
#   COPY_2D_FILES : yes | no
#                   yes -> copy 2D files unchanged into mirrored structure
#                   no  -> skip files without a vertical axis
#                   (default: yes)
# ==============================================================================
IN_ROOT="${IN_ROOT:-/home/SB5/ocean_downscaling_products}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/ocean_downscaling_products_bydepth}"
TMP_DIR="${TMP_DIR:-${OUT_ROOT}/tmp_split_bydepth}"
MIN_DECIMALS="${MIN_DECIMALS:-2}"
INTEGER_WIDTH="${INTEGER_WIDTH:-4}"
COPY_2D_FILES="${COPY_2D_FILES:-yes}"

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ "${COPY_2D_FILES}" != "yes" && "${COPY_2D_FILES}" != "no" ]]; then
  echo "ERROR: COPY_2D_FILES must be yes or no"
  exit 1
fi

mkdir -p "${OUT_ROOT}" "${TMP_DIR}"

find_vertical_dim() {
  local infile="$1"
  python3 - "$infile" <<'PY'
import sys
import xarray as xr

infile = sys.argv[1]
preferred = ["depth", "depth_below_sea", "lev", "z_t"]

with xr.open_dataset(infile) as ds:
    for name in preferred:
        if name in ds.dims:
            print(name)
            raise SystemExit(0)

    for var_name in ds.data_vars:
        dims = ds[var_name].dims
        for dim in preferred:
            if dim in dims:
                print(dim)
                raise SystemExit(0)

print("")
PY
}

depth_token_from_value() {
  local raw_value="$1"
  python3 - "$raw_value" "$MIN_DECIMALS" "$INTEGER_WIDTH" <<'PY'
import sys

value = float(sys.argv[1])
min_decimals = int(sys.argv[2])
integer_width = int(sys.argv[3])

formatted = f"{value:.{min_decimals}f}"
int_part, frac_part = formatted.split(".")
token = f"{int(int_part):0{integer_width}d}p{frac_part}"
print(f"{token}m")
PY
}

extract_all_levels() {
  local infile="$1"
  local out_dir="$2"
  local base="$3"
  local zdim="$4"

  python3 - "$infile" "$out_dir" "$base" "$zdim" "$MIN_DECIMALS" "$INTEGER_WIDTH" <<'PY'
import os
import sys
import xarray as xr

infile, out_dir, base, zdim = sys.argv[1:5]
min_decimals = int(sys.argv[5])
integer_width = int(sys.argv[6])

def depth_token(value: float) -> str:
    formatted = f"{float(value):.{min_decimals}f}"
    int_part, frac_part = formatted.split(".")
    return f"{int(int_part):0{integer_width}d}p{frac_part}m"

with xr.open_dataset(infile) as ds:
    if zdim not in ds.coords:
        raise ValueError(f"Vertical coordinate {zdim!r} not found in coords for {infile}")

    levels = ds.coords[zdim].values
    if getattr(levels, "ndim", 0) == 0:
        levels = [levels.item()]

    for idx, level_value in enumerate(levels):
        token = depth_token(float(level_value))
        outfile = os.path.join(out_dir, f"{base}_depth_{token}.nc")
        if os.path.exists(outfile):
          os.remove(outfile)
        # Keep the selected vertical coordinate as a scalar coordinate so later
        # export steps can recover the exact depth directly from the file.
        out = ds.isel({zdim: idx}, drop=False)
        out.to_netcdf(outfile)
        print(f"[DONE ] {outfile}")
PY
}

process_one_file() {
  local infile="$1"
  local rel_path rel_dir base out_dir zdim levels idx level_value level_token outfile

  rel_path="${infile#${IN_ROOT}/}"
  rel_dir="$(dirname "${rel_path}")"
  base="$(basename "${infile}" .nc)"
  out_dir="${OUT_ROOT}/${rel_dir}"

  mkdir -p "${out_dir}"

  if [[ ! -f "${infile}" ]]; then
    echo "[WARN] Source file disappeared before processing: ${rel_path}"
    return 0
  fi

  zdim="$(find_vertical_dim "${infile}")"
  if [[ -z "${zdim}" ]]; then
    if [[ "${COPY_2D_FILES}" == "yes" ]]; then
      cp -p "${infile}" "${out_dir}/"
      echo "[COPY] 2D/no-z file copied unchanged: ${rel_path}"
    else
      echo "[SKIP] No recognized vertical axis: ${rel_path}"
    fi
    return 0
  fi

  nlevels="$(cdo showlevel "${infile}" | tr ' ' '\n' | awk 'NF' | wc -l | tr -d ' ')"
  if [[ -z "${nlevels}" || "${nlevels}" == "0" ]]; then
    echo "[WARN] No levels returned by cdo showlevel for: ${rel_path}"
    if [[ "${COPY_2D_FILES}" == "yes" ]]; then
      cp -p "${infile}" "${out_dir}/"
      echo "[COPY] Falling back to unchanged copy: ${rel_path}"
    fi
    return 0
  fi

  echo
  echo "[START] ${rel_path}"
  echo "        zdim=${zdim} nlevels=${nlevels}"
  extract_all_levels "${infile}" "${out_dir}" "${base}" "${zdim}"
}

echo "============================================================"
echo "Starting curated ocean product split by depth"
echo "IN ROOT         : ${IN_ROOT}"
echo "OUT ROOT        : ${OUT_ROOT}"
echo "TMP DIR         : ${TMP_DIR}"
echo "MIN DECIMALS    : ${MIN_DECIMALS}"
echo "INTEGER WIDTH   : ${INTEGER_WIDTH}"
echo "COPY 2D FILES   : ${COPY_2D_FILES}"
echo "============================================================"

mapfile -t files < <(find "${IN_ROOT}" -type f -name "*.nc" | sort)
if (( ${#files[@]} == 0 )); then
  echo "ERROR: No NetCDF files found under: ${IN_ROOT}"
  exit 1
fi

for infile in "${files[@]}"; do
  process_one_file "${infile}"
done

echo
echo "All by-depth splitting completed."
