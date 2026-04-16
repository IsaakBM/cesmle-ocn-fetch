#!/usr/bin/env bash
# ==============================================================================
#  Curated ocean downscaling by-depth NetCDF to CSV exporter
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read curated by-depth NetCDF products from:
#        /home/SB5/ocean_downscaling_products_bydepth
#    - Mirror the same structure into:
#        /home/SB5/ocean_downscaling_products_bydepth_txt
#    - Export each 2D NetCDF file to a plain CSV table
#    - Write CSV columns as:
#        x,y,depth,<variable>_<units>
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=bydepth_csv
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH -t 1-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/bydepth_csv_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/bydepth_csv_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   IN_ROOT          : by-depth NetCDF root
#                      (default: /home/SB5/ocean_downscaling_products_bydepth)
#   OUT_ROOT         : mirrored CSV root
#                      (default: /home/SB5/ocean_downscaling_products_bydepth_txt)
#   TMP_DIR          : temp / bookkeeping directory
#                      (default: <OUT_ROOT>/tmp_export_csv)
#   DROP_MISSING     : yes | no
#                      yes -> drop rows where data value is missing
#                      no  -> keep rows with empty CSV values
#                      (default: yes)
# ==============================================================================
IN_ROOT="${IN_ROOT:-/home/SB5/ocean_downscaling_products_bydepth}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/ocean_downscaling_products_bydepth_txt}"
TMP_DIR="${TMP_DIR:-${OUT_ROOT}/tmp_export_csv}"
DROP_MISSING="${DROP_MISSING:-yes}"

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ "${DROP_MISSING}" != "yes" && "${DROP_MISSING}" != "no" ]]; then
  echo "ERROR: DROP_MISSING must be yes or no"
  exit 1
fi

mkdir -p "${OUT_ROOT}" "${TMP_DIR}"

process_one_file() {
  local infile="$1"
  local rel_path rel_dir base outfile

  rel_path="${infile#${IN_ROOT}/}"
  rel_dir="$(dirname "${rel_path}")"
  base="$(basename "${infile}" .nc)"
  outfile="${OUT_ROOT}/${rel_dir}/${base}.csv"

  mkdir -p "$(dirname "${outfile}")"
  rm -f "${outfile}"

  echo
  echo "[START] ${rel_path}"

  python3 - "${infile}" "${outfile}" "${DROP_MISSING}" <<'PY'
import sys
import re
import numpy as np
import pandas as pd
import xarray as xr

infile, outfile, drop_missing_flag = sys.argv[1], sys.argv[2], sys.argv[3]
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

def depth_from_filename(path: str):
    match = re.search(r"_depth_(\d+)p(\d+)m\.nc$", path)
    if not match:
        return np.nan
    return float(f"{int(match.group(1))}.{match.group(2)}")

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

    da = ds[main_var]
    # By-depth files can still carry singleton dimensions such as time=1.
    # Collapse those before checking for the final horizontal field.
    da = da.squeeze(drop=True)

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

    depth_value = np.nan
    for depth_name in ["depth", "depth_below_sea", "lev", "z_t"]:
        if depth_name in ds.coords:
            depth_da = ds[depth_name].squeeze(drop=True)
            if depth_da.ndim == 0:
                depth_value = float(depth_da.values)
                break
        elif depth_name in ds:
            depth_da = ds[depth_name].squeeze(drop=True)
            if depth_da.ndim == 0:
                depth_value = float(depth_da.values)
                break

    if np.isnan(depth_value):
        depth_value = depth_from_filename(infile)

    values = da.values
    if values.ndim != 2:
        raise SystemExit(f"Expected a 2D variable in {infile}, got ndim={values.ndim}")

    if values.shape != xx.shape or values.shape != yy.shape:
        raise SystemExit(
            f"Shape mismatch in {infile}: data={values.shape}, x={xx.shape}, y={yy.shape}"
        )

    units = sanitize_units(str(da.attrs.get("units", "")))
    value_column = f"{main_var}_{units}"

    df = pd.DataFrame(
        {
            "x": xx.ravel(),
            "y": yy.ravel(),
            "depth": np.full(xx.size, depth_value),
            value_column: values.ravel(),
        }
    )

    if drop_missing:
        df = df[df[value_column].notna()]

    df.to_csv(outfile, index=False)
PY

  echo "[DONE ] ${outfile}"
}

echo "============================================================"
echo "Starting by-depth NetCDF to CSV export"
echo "IN ROOT         : ${IN_ROOT}"
echo "OUT ROOT        : ${OUT_ROOT}"
echo "TMP DIR         : ${TMP_DIR}"
echo "DROP MISSING    : ${DROP_MISSING}"
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
echo "All by-depth CSV exports completed."
