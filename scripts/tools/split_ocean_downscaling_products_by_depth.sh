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
#   FUTURE_MODELS : auto or space-separated future top-level branches to include
#                   (default: auto)
#   EXCLUDE_FUTURE_MODELS
#                 : space-separated future top-level branches to exclude
#                   (default: cesm_f09_g16 legacy_downscaled_rcp85; empty clears)
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
FUTURE_MODELS="${FUTURE_MODELS:-auto}"
# Production selection: omit retired branches; retain discovery of new models.
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS-cesm_f09_g16 legacy_downscaled_rcp85}"
NPROC="${SLURM_CPUS_PER_TASK:-6}"
read -r -a FUTURE_MODEL_LIST <<< "${FUTURE_MODELS}"
read -r -a EXCLUDE_FUTURE_MODEL_LIST <<< "${EXCLUDE_FUTURE_MODELS}"

contains_word() {
  local needle="$1"
  shift
  local candidate

  for candidate in "$@"; do
    [[ "${candidate}" == "${needle}" ]] && return 0
  done
  return 1
}

include_relative_path() {
  local rel_path="$1"
  local model

  # Recover the model component when IN_ROOT is already inside a future subtree.
  # Keep rel_path used for output layout unchanged outside this filter.
  local selection_path="${MODEL_SELECTION_ROOT}/${rel_path}"
  case "${selection_path}" in
    */future/*) rel_path="future/${selection_path##*/future/}" ;;
    */baseline/*) rel_path="baseline/${selection_path##*/baseline/}" ;;
  esac

  case "${rel_path}" in
    baseline/*)
      return 0
      ;;
    future/*)
      model="${rel_path#future/}"
      model="${model%%/*}"
      if [[ -n "${EXCLUDE_FUTURE_MODELS}" ]] && contains_word "${model}" "${EXCLUDE_FUTURE_MODEL_LIST[@]}"; then
        return 1
      fi
      if [[ "${FUTURE_MODELS}" != "auto" ]] && ! contains_word "${model}" "${FUTURE_MODEL_LIST[@]}"; then
        return 1
      fi
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi
# Resolve a relative input root once, including direct subtree invocations.
MODEL_SELECTION_ROOT="$(cd "${IN_ROOT}" && pwd -P)"

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

# Atomic publication owns only its lock and private workspace. A pre-existing
# lock is never removed automatically; interrupted writers require inspection.
from contextlib import contextmanager
import os
import shutil
import signal
import tempfile

@contextmanager
def atomic_product(final, overwrite=True):
    os.makedirs(os.path.dirname(final), exist_ok=True)
    lock = final + ".lock"
    try:
        os.mkdir(lock)
    except FileExistsError:
        raise RuntimeError(f"Output locked by another writer (or stale lock): {final}")
    work = None
    previous = signal.getsignal(signal.SIGTERM)
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)
    try:
        signal.signal(signal.SIGTERM, interrupted)
        if os.path.exists(final) and not overwrite:
            print(f"[SKIP] Existing output retained; freshness not verified: {final}")
            yield None
            return
        work = tempfile.mkdtemp(prefix="." + os.path.basename(final) + ".work.",
                                dir=os.path.dirname(final))
        candidate = os.path.join(work, os.path.basename(final))
        yield candidate
        if not os.path.isfile(candidate) or os.path.getsize(candidate) == 0:
            raise RuntimeError(f"Writer did not create a nonempty candidate: {final}")
        os.replace(candidate, final)
    finally:
        signal.signal(signal.SIGTERM, previous)
        if work is not None:
            shutil.rmtree(work)
        os.rmdir(lock)

def publish_netcdf(dataset, final, overwrite=True):
    with atomic_product(final, overwrite) as candidate:
        if candidate is None:
            return
        dataset.to_netcdf(candidate)
        # Read every field back before replacing the accepted file.
        with xr.open_dataset(candidate) as check:
            check.load()
            xr.testing.assert_identical(check, dataset)
            if dict(check.sizes) != dict(dataset.sizes) or set(check.variables) != set(dataset.variables):
                raise ValueError(f"Replacement structure differs: {final}")

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
        # Keep the selected vertical coordinate as a scalar coordinate so later
        # export steps can recover the exact depth directly from the file.
        out = ds.isel({zdim: idx}, drop=False)
        publish_netcdf(out, outfile)
        print(f"[DONE ] {outfile} depth_m={depth_value:.10g}")
        exported += 1

    if max_depth is not None:
        print(f"[INFO ] {base}: exported {exported} levels with {zdim} <= {max_depth:g} m; skipped {skipped} deeper levels")
PY
}

copy_2d_atomically() {
  python3 - "$1" "$2" <<'PY_COPY_ATOMIC'
import sys
import filecmp
import xarray as xr
# Atomic publication owns only its lock and private workspace. A pre-existing
# lock is never removed automatically; interrupted writers require inspection.
from contextlib import contextmanager
import os
import shutil
import signal
import tempfile

@contextmanager
def atomic_product(final, overwrite=True):
    os.makedirs(os.path.dirname(final), exist_ok=True)
    lock = final + ".lock"
    try:
        os.mkdir(lock)
    except FileExistsError:
        raise RuntimeError(f"Output locked by another writer (or stale lock): {final}")
    work = None
    previous = signal.getsignal(signal.SIGTERM)
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)
    try:
        signal.signal(signal.SIGTERM, interrupted)
        if os.path.exists(final) and not overwrite:
            print(f"[SKIP] Existing output retained; freshness not verified: {final}")
            yield None
            return
        work = tempfile.mkdtemp(prefix="." + os.path.basename(final) + ".work.",
                                dir=os.path.dirname(final))
        candidate = os.path.join(work, os.path.basename(final))
        yield candidate
        if not os.path.isfile(candidate) or os.path.getsize(candidate) == 0:
            raise RuntimeError(f"Writer did not create a nonempty candidate: {final}")
        os.replace(candidate, final)
    finally:
        signal.signal(signal.SIGTERM, previous)
        if work is not None:
            shutil.rmtree(work)
        os.rmdir(lock)

source, final = sys.argv[1:]
with atomic_product(final) as candidate:
    shutil.copy2(source, candidate)
    if not filecmp.cmp(source, candidate, shallow=False):
        raise ValueError("Copied NetCDF differs from source")
    with xr.open_dataset(candidate) as check:
        check.load()
PY_COPY_ATOMIC
}

process_one_file() (
  set -euo pipefail
  local infile="$1"
  local rel_path rel_dir base out_dir zdim levels idx level_value level_token outfile

  rel_path="${infile#${IN_ROOT}/}"
  rel_dir="$(dirname "${rel_path}")"
  base="$(basename "${infile}" .nc)"
  out_dir="${OUT_ROOT}/${rel_dir}"

  mkdir -p "${out_dir}"

  if [[ ! -f "${infile}" ]]; then
    echo "[ERROR] Source file disappeared before processing: ${rel_path}" >&2
    return 1
  fi

  zdim="$(find_vertical_dim "${infile}")"
  if [[ -z "${zdim}" ]]; then
    if [[ "${COPY_2D_FILES}" == "yes" ]]; then
      copy_2d_atomically "${infile}" "${out_dir}/$(basename "$infile")"
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
      copy_2d_atomically "${infile}" "${out_dir}/$(basename "$infile")"
      echo "[COPY] Falling back to unchanged copy: ${rel_path}"
    fi
    return 0
  fi

  echo
  echo "[START] ${rel_path}"
  echo "        zdim=${zdim} nlevels=${nlevels}"
  extract_all_levels "${infile}" "${out_dir}" "${base}" "${zdim}"
)

echo "============================================================"
echo "Starting curated ocean product split by depth"
echo "IN ROOT         : ${IN_ROOT}"
echo "OUT ROOT        : ${OUT_ROOT}"
echo "TMP DIR         : ${TMP_DIR}"
echo "MAX DEPTH M     : ${MAX_DEPTH_M:-<all>}"
echo "MIN DECIMALS    : ${MIN_DECIMALS}"
echo "INTEGER WIDTH   : ${INTEGER_WIDTH}"
echo "COPY 2D FILES   : ${COPY_2D_FILES}"
echo "FUTURE MODELS   : ${FUTURE_MODELS}"
echo "EXCLUDE FUTURE  : ${EXCLUDE_FUTURE_MODELS:-<none>}"
echo "PARALLEL FILES  : ${NPROC}"
echo "============================================================"

mapfile -t files < <(
  while IFS= read -r file; do
    rel_path="${file#${IN_ROOT}/}"
    include_relative_path "${rel_path}" && printf '%s\n' "${file}"
  done < <(find "${IN_ROOT}" -type f -name "*.nc" | sort)
)
if (( ${#files[@]} == 0 )); then
  echo "ERROR: No NetCDF files found under: ${IN_ROOT}"
  exit 1
fi

for infile in "${files[@]}"; do
  :
done

export IN_ROOT OUT_ROOT TMP_DIR MAX_DEPTH_M MIN_DECIMALS INTEGER_WIDTH COPY_2D_FILES
export -f copy_2d_atomically find_vertical_dim depth_token_from_value extract_all_levels process_one_file

printf '%s\0' "${files[@]}" \
  | xargs -0 -n 1 -P "${NPROC}" bash -c 'process_one_file "$1"' _

echo
echo "All by-depth splitting completed."
