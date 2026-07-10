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
#SBATCH --cpus-per-task=6
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
#                   (default: /home/SB5/ocean_downscaling_products_bydepth,
#                   or /home/SB5/ocean_downscaling_products_depths when
#                   MAX_DEPTH_M is set)
#   TMP_DIR       : temp / bookkeeping directory
#                   (default: <OUT_ROOT>/tmp_split_bydepth)
#   MAX_DEPTH_M   : optional maximum depth center to export, in meters
#                   empty/all -> export all depths
#   MIN_DECIMALS  : decimals in depth token (default: 3)
#                   increase if a source file has depth-token collisions
#   INTEGER_WIDTH : zero-padded width for the integer part of depth tokens
#                   (default: 4)
#   COPY_2D_FILES : yes | no
#                   yes -> copy 2D files unchanged into mirrored structure
#                   no  -> skip files without a vertical axis
#                   (default: yes)
# ==============================================================================
IN_ROOT="${IN_ROOT:-/home/SB5/ocean_downscaling_products}"
MAX_DEPTH_M="${MAX_DEPTH_M:-}"
MAX_DEPTH_M_LOWER="${MAX_DEPTH_M,,}"
if [[ -z "${OUT_ROOT:-}" ]]; then
  if [[ -n "${MAX_DEPTH_M}" && "${MAX_DEPTH_M_LOWER}" != "all" ]]; then
    OUT_ROOT="/home/SB5/ocean_downscaling_products_depths"
  else
    OUT_ROOT="/home/SB5/ocean_downscaling_products_bydepth"
  fi
fi
TMP_DIR="${TMP_DIR:-${OUT_ROOT}/tmp_split_bydepth}"
MIN_DECIMALS="${MIN_DECIMALS:-3}"
INTEGER_WIDTH="${INTEGER_WIDTH:-4}"
COPY_2D_FILES="${COPY_2D_FILES:-yes}"
NPROC="${SLURM_CPUS_PER_TASK:-6}"

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ "${COPY_2D_FILES}" != "yes" && "${COPY_2D_FILES}" != "no" ]]; then
  echo "ERROR: COPY_2D_FILES must be yes or no"
  exit 1
fi

if [[ -n "${MAX_DEPTH_M}" && "${MAX_DEPTH_M_LOWER}" != "all" ]]; then
  python3 - "${MAX_DEPTH_M}" <<'PY'
import sys
value = float(sys.argv[1])
if value < 0:
    raise SystemExit("MAX_DEPTH_M must be >= 0")
PY
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

  python3 - "$infile" "$out_dir" "$base" "$zdim" "$MIN_DECIMALS" "$INTEGER_WIDTH" "$MAX_DEPTH_M" <<'PY'
import os
import sys
import xarray as xr

infile, out_dir, base, zdim = sys.argv[1:5]
min_decimals = int(sys.argv[5])
integer_width = int(sys.argv[6])
max_depth_text = sys.argv[7]
max_depth = None if max_depth_text.lower() in ("", "all") else float(max_depth_text)

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

    exported = 0
    skipped = 0
    selected = []
    tokens = {}
    for idx, level_value in enumerate(levels):
        depth_value = float(level_value)
        if max_depth is not None and depth_value > max_depth:
            skipped += 1
            continue

        token = depth_token(depth_value)
        if token in tokens:
            other_idx, other_depth = tokens[token]
            raise ValueError(
                f"Depth token collision in {infile}: "
                f"level {other_idx} depth={other_depth} and level {idx} depth={depth_value} "
                f"both map to depth_{token}. Increase MIN_DECIMALS."
            )
        tokens[token] = (idx, depth_value)
        selected.append((idx, depth_value, token))

    for idx, depth_value, token in selected:
        outfile = os.path.join(out_dir, f"{base}_depth_{token}.nc")
        if os.path.exists(outfile):
          os.remove(outfile)
        # Keep the selected vertical coordinate as a scalar coordinate so later
        # export steps can recover the exact depth directly from the file.
        out = ds.isel({zdim: idx}, drop=False)
        out.to_netcdf(outfile)
        print(f"[DONE ] {outfile} depth_m={depth_value:.10g}")
        exported += 1

    if max_depth is not None:
        print(f"[INFO ] {base}: exported {exported} levels with {zdim} <= {max_depth:g} m; skipped {skipped} deeper levels")
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
echo "MAX DEPTH M     : ${MAX_DEPTH_M:-<all>}"
echo "MIN DECIMALS    : ${MIN_DECIMALS}"
echo "INTEGER WIDTH   : ${INTEGER_WIDTH}"
echo "COPY 2D FILES   : ${COPY_2D_FILES}"
echo "PARALLEL FILES  : ${NPROC}"
echo "============================================================"

mapfile -t files < <(find "${IN_ROOT}" -type f -name "*.nc" | sort)
if (( ${#files[@]} == 0 )); then
  echo "ERROR: No NetCDF files found under: ${IN_ROOT}"
  exit 1
fi

for infile in "${files[@]}"; do
  :
done

export IN_ROOT OUT_ROOT TMP_DIR MAX_DEPTH_M MIN_DECIMALS INTEGER_WIDTH COPY_2D_FILES
export -f find_vertical_dim depth_token_from_value extract_all_levels process_one_file

printf '%s\0' "${files[@]}" \
  | xargs -0 -n 1 -P "${NPROC}" bash -c 'process_one_file "$1"' _

echo
echo "All by-depth splitting completed."
