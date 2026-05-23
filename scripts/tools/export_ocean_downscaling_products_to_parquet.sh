#!/usr/bin/env bash
# ==============================================================================
#  Curated ocean downscaling NetCDF to Parquet exporter
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read curated aggregated NetCDF products from a mirrored product tree
#    - Mirror the same structure into a Parquet tree
#    - Export each 2D NetCDF file to a columnar Parquet table
#    - Write Parquet columns in the same style as the older CSV workflow:
#        x,y,depth,<variable>_<units>
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=to_parquet
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=5
#SBATCH --mem=128G
#SBATCH -t 1-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/to_parquet_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/to_parquet_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   IN_ROOT          : NetCDF input root
#   OUT_ROOT         : mirrored Parquet output root
#   TMP_DIR          : temp / bookkeeping directory
#                      (default: <OUT_ROOT>/tmp_export_parquet)
#   DROP_MISSING     : yes | no
#                      yes -> drop rows where data value is missing
#                      no  -> keep rows with null parquet values
#                      (default: yes)
#   PARQUET_PYTHON   : Python interpreter with pandas, pyarrow, and xarray
#                      available
#                      (default: /home/ibrito/venvs/parquet_export/bin/python)
#   PARQUET_ENGINE   : parquet backend for pandas
#                      (default: pyarrow)
#   NPROC            : number of files to process in parallel
#                      (default: SLURM_CPUS_PER_TASK or 5)
#   OVERWRITE        : yes | no
#                      yes -> replace existing outputs
#                      no  -> keep existing outputs
#                      (default: no)
# ==============================================================================
IN_ROOT="${IN_ROOT:-/home/SB5/ocean_downscaling_products_layers}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/ocean_downscaling_products_layers_parquet}"
TMP_DIR="${TMP_DIR:-${OUT_ROOT}/tmp_export_parquet}"
DROP_MISSING="${DROP_MISSING:-yes}"
PARQUET_PYTHON="${PARQUET_PYTHON:-/home/ibrito/venvs/parquet_export/bin/python}"
PARQUET_ENGINE="${PARQUET_ENGINE:-pyarrow}"
NPROC="${NPROC:-${SLURM_CPUS_PER_TASK:-5}}"
OVERWRITE="${OVERWRITE:-no}"

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ "${DROP_MISSING}" != "yes" && "${DROP_MISSING}" != "no" ]]; then
  echo "ERROR: DROP_MISSING must be yes or no"
  exit 1
fi

if [[ "${OVERWRITE}" != "yes" && "${OVERWRITE}" != "no" ]]; then
  echo "ERROR: OVERWRITE must be yes or no"
  exit 1
fi

if [[ ! -x "${PARQUET_PYTHON}" ]]; then
  echo "ERROR: PARQUET_PYTHON is not executable: ${PARQUET_PYTHON}"
  exit 1
fi

mkdir -p "${OUT_ROOT}" "${TMP_DIR}"

"${PARQUET_PYTHON}" - <<'PY'
import importlib
mods = ["numpy", "pandas", "pyarrow", "xarray"]
missing = []
for name in mods:
    try:
        importlib.import_module(name)
    except Exception as exc:
        missing.append(f"{name}: {exc}")

backend_ok = False
for backend in ["netCDF4", "h5netcdf"]:
    try:
        importlib.import_module(backend)
        backend_ok = True
        break
    except Exception:
        pass

if not backend_ok:
    missing.append("Need at least one xarray NetCDF backend: netCDF4 or h5netcdf")

if missing:
    raise SystemExit("Missing Python dependencies for Parquet export:\n" + "\n".join(missing))
PY

process_one_file() {
  local infile="$1"
  local rel_path rel_dir base outfile

  rel_path="${infile#${IN_ROOT}/}"
  rel_dir="$(dirname "${rel_path}")"
  base="$(basename "${infile}" .nc)"
  outfile="${OUT_ROOT}/${rel_dir}/${base}.parquet"

  mkdir -p "$(dirname "${outfile}")"
  if [[ -f "${outfile}" && "${OVERWRITE}" == "no" ]]; then
    echo "[SKIP ] ${outfile} exists (OVERWRITE=no)"
    return 0
  fi
  rm -f "${outfile}"

  echo
  echo "[START] ${rel_path}"

  "${PARQUET_PYTHON}" - "${infile}" "${outfile}" "${DROP_MISSING}" "${PARQUET_ENGINE}" <<'PY'
import os
import re
import sys
import numpy as np
import pandas as pd
import xarray as xr

infile, outfile, drop_missing_flag, parquet_engine = sys.argv[1:5]
drop_missing = drop_missing_flag == "yes"

preferred_xy = [
    ("lon", "lat"),
    ("longitude", "latitude"),
    ("x", "y"),
]

ignored_vars = {"time_bnds", "lat_bnds", "lon_bnds", "depth_bnds"}

def sanitize_units(units: str) -> str:
    text = (units or "").strip()
    if not text:
        return "unitless"
    text = text.replace(" ", "")
    text = text.replace("/", "per")
    text = re.sub(r"[^A-Za-z0-9+-]", "", text)
    return text or "unitless"

with xr.open_dataset(infile) as ds:
    data_vars = [v for v in ds.data_vars if v not in ignored_vars]
    if not data_vars:
        raise SystemExit(f"No usable data variable found in {infile}")

    main_var = None
    for candidate in data_vars:
        if ds[candidate].ndim >= 2:
            main_var = candidate
            break

    if main_var is None:
        main_var = data_vars[0]

    da = ds[main_var].squeeze(drop=True)

    x_name = None
    y_name = None
    for x_candidate, y_candidate in preferred_xy:
        if x_candidate in ds and y_candidate in ds:
            x_name = x_candidate
            y_name = y_candidate
            break

    if x_name is None or y_name is None:
        if "lon" in da.coords and "lat" in da.coords:
            x_name, y_name = "lon", "lat"
        else:
            raise SystemExit(f"Could not identify x/y coordinates in {infile}")

    xcoord = ds[x_name]
    ycoord = ds[y_name]

    if xcoord.ndim == 1 and ycoord.ndim == 1:
        xx, yy = np.meshgrid(xcoord.values, ycoord.values)
    elif xcoord.ndim == 2 and ycoord.ndim == 2:
        xx, yy = xcoord.values, ycoord.values
    else:
        raise SystemExit(f"Unsupported coordinate dimensionality in {infile}")

    values = da.values
    if values.ndim != 2:
        raise SystemExit(f"Expected a 2D variable in {infile}, got ndim={values.ndim}")

    if values.shape != xx.shape or values.shape != yy.shape:
        raise SystemExit(
            f"Shape mismatch in {infile}: data={values.shape}, x={xx.shape}, y={yy.shape}"
        )

    units = sanitize_units(str(da.attrs.get("units", "")))
    value_column = f"{main_var}_{units}"

    base = os.path.basename(infile)
    depth_value = None
    match = re.search(r"_(layer|zone)_([A-Za-z0-9]+(?:_[0-9]{4}_[0-9]{4}m)|[0-9]{4}_[0-9]{4}m)\.nc$", base)
    if match:
        depth_value = match.group(2)
    else:
        for attr_name in ["depth_bin_label", "depth_bin_lower_m", "depth_bin_upper_m"]:
            if attr_name in ds.attrs:
                depth_value = str(ds.attrs[attr_name])
                break
    if depth_value is None:
        raise SystemExit(f"Could not derive depth label from filename or metadata in {infile}")

    columns = {
        "x": xx.ravel(),
        "y": yy.ravel(),
        "depth": np.full(xx.size, depth_value),
        value_column: values.ravel(),
    }

    df = pd.DataFrame(columns)

    if drop_missing:
        df = df[df[value_column].notna()]

    df.to_parquet(outfile, index=False, engine=parquet_engine)
PY

  echo "[DONE ] ${outfile}"
}

echo "============================================================"
echo "Starting NetCDF to Parquet export"
echo "IN ROOT         : ${IN_ROOT}"
echo "OUT ROOT        : ${OUT_ROOT}"
echo "TMP DIR         : ${TMP_DIR}"
echo "DROP MISSING    : ${DROP_MISSING}"
echo "PARQUET PYTHON  : ${PARQUET_PYTHON}"
echo "PARQUET ENGINE  : ${PARQUET_ENGINE}"
echo "PARALLEL FILES  : ${NPROC}"
echo "OVERWRITE       : ${OVERWRITE}"
echo "============================================================"

mapfile -t files < <(find "${IN_ROOT}" -type f -name "*.nc" | sort)
if (( ${#files[@]} == 0 )); then
  echo "ERROR: No NetCDF files found under: ${IN_ROOT}"
  exit 1
fi

"${PARQUET_PYTHON}" - "${files[0]}" <<'PY'
import sys
import xarray as xr

infile = sys.argv[1]
try:
    with xr.open_dataset(infile):
        pass
except Exception as exc:
    raise SystemExit(
        "Parquet export preflight failed before processing files.\n"
        f"Could not open NetCDF input with the configured Python environment: {infile}\n"
        f"Reason: {exc}"
    )
PY

export IN_ROOT OUT_ROOT TMP_DIR DROP_MISSING PARQUET_PYTHON PARQUET_ENGINE OVERWRITE
export -f process_one_file

printf '%s\0' "${files[@]}" \
  | xargs -0 -n 1 -P "${NPROC}" bash -c 'process_one_file "$1"' _

echo
echo "All NetCDF to Parquet exports completed."
