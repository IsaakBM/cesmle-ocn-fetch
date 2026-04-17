#!/usr/bin/env bash
# ==============================================================================
#  Curated ocean downscaling product aggregation by depth bins
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
#    - Mirror the same baseline/future structure into a binned-depth tree
#    - Aggregate each 3D NetCDF file into one NetCDF file per configured
#      vertical depth bin
#    - Write thickness-weighted means using explicit or reconstructed
#      vertical bounds
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=depth_bins
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=6
#SBATCH --mem=512G
#SBATCH -t 1-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/depth_bins_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/depth_bins_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   IN_ROOT       : curated input root (default: /home/SB5/ocean_downscaling_products)
#   OUT_ROOT      : aggregated output root
#                   fine    -> /home/SB5/ocean_downscaling_products_layers
#                   pelagic -> /home/SB5/ocean_downscaling_products_pelagic
#   TMP_DIR       : temp / bookkeeping directory
#                   (default: <OUT_ROOT>/tmp_depth_bins)
#   BIN_SET       : fine | pelagic
#                   (default: fine)
#   COPY_2D_FILES : yes | no
#                   yes -> copy 2D files unchanged into mirrored structure
#                   no  -> skip files without a vertical axis
#                   (default: yes)
#   OVERWRITE     : yes | no
#                   yes -> replace existing outputs
#                   no  -> keep existing outputs
#                   (default: yes)
# ==============================================================================
IN_ROOT="${IN_ROOT:-/home/SB5/ocean_downscaling_products}"
BIN_SET="${BIN_SET:-fine}"

case "${BIN_SET}" in
  fine)
    DEFAULT_OUT_ROOT="/home/SB5/ocean_downscaling_products_layers"
    ;;
  pelagic)
    DEFAULT_OUT_ROOT="/home/SB5/ocean_downscaling_products_pelagic"
    ;;
  *)
    echo "ERROR: BIN_SET must be fine or pelagic"
    exit 1
    ;;
esac

OUT_ROOT="${OUT_ROOT:-${DEFAULT_OUT_ROOT}}"
TMP_DIR="${TMP_DIR:-${OUT_ROOT}/tmp_depth_bins}"
COPY_2D_FILES="${COPY_2D_FILES:-yes}"
OVERWRITE="${OVERWRITE:-yes}"
NPROC="${SLURM_CPUS_PER_TASK:-6}"

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ "${COPY_2D_FILES}" != "yes" && "${COPY_2D_FILES}" != "no" ]]; then
  echo "ERROR: COPY_2D_FILES must be yes or no"
  exit 1
fi

if [[ "${OVERWRITE}" != "yes" && "${OVERWRITE}" != "no" ]]; then
  echo "ERROR: OVERWRITE must be yes or no"
  exit 1
fi

mkdir -p "${OUT_ROOT}" "${TMP_DIR}"

process_one_file() {
  local infile="$1"
  local rel_path rel_dir out_dir

  rel_path="${infile#${IN_ROOT}/}"
  rel_dir="$(dirname "${rel_path}")"
  out_dir="${OUT_ROOT}/${rel_dir}"

  mkdir -p "${out_dir}"

  if [[ ! -f "${infile}" ]]; then
    echo "[WARN] Source file disappeared before processing: ${rel_path}"
    return 0
  fi

  echo
  echo "[START] ${rel_path}"

  python3 - "${infile}" "${out_dir}" "${BIN_SET}" "${COPY_2D_FILES}" "${OVERWRITE}" <<'PY'
import os
import sys
import numpy as np
import xarray as xr

infile, out_dir, bin_set, copy_2d_flag, overwrite_flag = sys.argv[1:6]
copy_2d = copy_2d_flag == "yes"
overwrite = overwrite_flag == "yes"

preferred_zdims = ["depth", "depth_below_sea", "lev", "z_t"]
ignored_vars = {"time_bnds", "lat_bnds", "lon_bnds", "depth_bnds", "lev_bnds", "z_t_bnds"}

bin_definitions = {
    "fine": [
        ("layer", "0000_0025m", "0-25 m", 0.0, 25.0),
        ("layer", "0025_0050m", "25-50 m", 25.0, 50.0),
        ("layer", "0050_0100m", "50-100 m", 50.0, 100.0),
        ("layer", "0100_0200m", "100-200 m", 100.0, 200.0),
        ("layer", "0200_0400m", "200-400 m", 200.0, 400.0),
        ("layer", "0400_0600m", "400-600 m", 400.0, 600.0),
        ("layer", "0600_0800m", "600-800 m", 600.0, 800.0),
        ("layer", "0800_1000m", "800-1000 m", 800.0, 1000.0),
        ("layer", "1000_1500m", "1000-1500 m", 1000.0, 1500.0),
        ("layer", "1500_2000m", "1500-2000 m", 1500.0, 2000.0),
        ("layer", "2000_3000m", "2000-3000 m", 2000.0, 3000.0),
        ("layer", "3000_4000m", "3000-4000 m", 3000.0, 4000.0),
        ("layer", "4000_5000m", "4000-5000 m", 4000.0, 5000.0),
        ("layer", "5000_6000m", "5000-6000 m", 5000.0, 6000.0),
    ],
    "pelagic": [
        ("zone", "epipelagic_0000_0200m", "Epipelagic", 0.0, 200.0),
        ("zone", "mesopelagic_0200_1000m", "Mesopelagic", 200.0, 1000.0),
        ("zone", "bathypelagic_1000_4000m", "Bathypelagic", 1000.0, 4000.0),
        ("zone", "abyssopelagic_4000_6000m", "Abyssopelagic", 4000.0, 6000.0),
    ],
}

def choose_zdim(ds: xr.Dataset):
    for name in preferred_zdims:
        if name in ds.dims:
            return name
    for var_name in ds.data_vars:
        dims = ds[var_name].dims
        for name in preferred_zdims:
            if name in dims:
                return name
    return None

def choose_main_var(ds: xr.Dataset, zdim: str):
    for name in ds.data_vars:
        if name in ignored_vars:
            continue
        if zdim in ds[name].dims:
            return name
    for name in ds.data_vars:
        if name not in ignored_vars:
            return name
    return None

def detect_bounds(ds: xr.Dataset, zdim: str):
    coord = ds[zdim]
    bounds_name = coord.attrs.get("bounds")
    if bounds_name and bounds_name in ds:
        return bounds_name, "explicit_bounds"

    candidates = [
        f"{zdim}_bnds",
        f"{zdim}_bounds",
        "depth_bnds",
        "depth_bounds",
        "lev_bnds",
        "lev_bounds",
    ]
    for candidate in candidates:
        if candidate in ds:
            return candidate, "explicit_bounds"

    return None, "reconstructed_bounds"

def reconstruct_bounds(levels: np.ndarray):
    levels = np.asarray(levels, dtype=float)
    if levels.ndim != 1 or levels.size == 0:
        raise ValueError("Need a non-empty 1D level array to reconstruct bounds")

    bounds = np.empty((levels.size, 2), dtype=float)

    if levels.size == 1:
        top = max(0.0, levels[0] / 2.0)
        bottom = levels[0] + max(levels[0] - top, 1.0)
        bounds[0, 0] = top
        bounds[0, 1] = bottom
        return bounds

    interfaces = (levels[:-1] + levels[1:]) / 2.0
    top_interface = max(0.0, levels[0] - (interfaces[0] - levels[0]))
    bottom_interface = levels[-1] + (levels[-1] - interfaces[-1])

    bounds[0, 0] = top_interface
    bounds[0, 1] = interfaces[0]

    for idx in range(1, levels.size - 1):
        bounds[idx, 0] = interfaces[idx - 1]
        bounds[idx, 1] = interfaces[idx]

    bounds[-1, 0] = interfaces[-1]
    bounds[-1, 1] = bottom_interface
    return bounds

def normalize_bounds(bounds, zdim: str):
    arr = np.asarray(bounds, dtype=float)
    if arr.ndim != 2:
        raise ValueError("Bounds variable must be 2D")
    if arr.shape[0] != ds.sizes[zdim]:
        raise ValueError("Bounds variable does not align with vertical dimension")
    if arr.shape[1] != 2:
        if arr.shape[0] == 2 and arr.shape[1] == ds.sizes[zdim]:
            arr = arr.T
        else:
            raise ValueError("Bounds variable must have a size-2 edge dimension")
    lower = np.minimum(arr[:, 0], arr[:, 1])
    upper = np.maximum(arr[:, 0], arr[:, 1])
    return np.column_stack([lower, upper])

with xr.open_dataset(infile) as ds:
    zdim = choose_zdim(ds)
    if zdim is None:
        rel_copy = os.path.join(out_dir, os.path.basename(infile))
        if copy_2d:
            if overwrite and os.path.exists(rel_copy):
                os.remove(rel_copy)
            if overwrite or not os.path.exists(rel_copy):
                ds.load()
                ds.to_netcdf(rel_copy)
            print(f"[COPY] 2D/no-z file copied unchanged: {infile}")
        else:
            print(f"[SKIP] No recognized vertical axis: {infile}")
        raise SystemExit(0)

    main_var = choose_main_var(ds, zdim)
    if main_var is None:
        raise SystemExit(f"No usable data variable found in {infile}")

    base = os.path.splitext(os.path.basename(infile))[0]
    levels = np.asarray(ds[zdim].values, dtype=float)
    if levels.ndim == 0:
        levels = np.asarray([float(levels)])

    bounds_name, bounds_source = detect_bounds(ds, zdim)
    if bounds_name is not None:
        bounds = normalize_bounds(ds[bounds_name].values, zdim)
    else:
        bounds = reconstruct_bounds(levels)

    thickness = bounds[:, 1] - bounds[:, 0]
    if np.any(thickness <= 0):
        raise SystemExit(f"Non-positive layer thickness encountered in {infile}")

    print(
        f"[INFO ] zdim={zdim} main_var={main_var} nlevels={levels.size} "
        f"bounds_source={bounds_source}"
    )

    for prefix, slug, label, lower, upper in bin_definitions[bin_set]:
        mask = (levels >= lower) & (levels < upper)
        idx = np.where(mask)[0]
        if idx.size == 0:
            print(f"[SKIP] {slug} has no matching levels")
            continue

        outfile = os.path.join(out_dir, f"{base}_{prefix}_{slug}.nc")
        if os.path.exists(outfile) and not overwrite:
            print(f"[KEEP] {outfile}")
            continue
        if os.path.exists(outfile):
            os.remove(outfile)

        if idx.size == 1:
            out = ds[[main_var]].isel({zdim: idx[0]}, drop=True)
            method = "single_level"
        else:
            selected = ds[main_var].isel({zdim: idx})
            selected_weights = xr.DataArray(
                thickness[idx],
                dims=(zdim,),
                coords={zdim: ds[zdim].isel({zdim: idx}).values},
                name="layer_thickness",
            )
            weighted_sum = (selected * selected_weights).sum(dim=zdim, skipna=True)
            valid_weight_sum = selected_weights.where(selected.notnull()).sum(dim=zdim, skipna=True)
            aggregated = xr.where(valid_weight_sum > 0, weighted_sum / valid_weight_sum, np.nan)
            out = aggregated.to_dataset(name=main_var)
            method = "weighted_mean"

        for coord_name in ds.coords:
            if coord_name == zdim:
                continue
            if coord_name not in out.coords and coord_name not in out.data_vars:
                coord = ds[coord_name]
                if zdim not in coord.dims:
                    out = out.assign_coords({coord_name: coord})

        out.attrs = ds.attrs.copy()
        out.attrs["depth_bin_label"] = label
        out.attrs["depth_bin_lower_m"] = float(lower)
        out.attrs["depth_bin_upper_m"] = float(upper)
        out.attrs["depth_bin_mode"] = bin_set
        out.attrs["vertical_aggregation_method"] = method
        out.attrs["vertical_bounds_source"] = bounds_source

        out[main_var].attrs = ds[main_var].attrs.copy()
        cell_methods = out[main_var].attrs.get("cell_methods", "").strip()
        z_method = f"{zdim}: mean"
        if z_method not in cell_methods.split():
            out[main_var].attrs["cell_methods"] = (
                f"{cell_methods} {z_method}".strip() if cell_methods else z_method
            )

        out.to_netcdf(outfile)
        print(
            f"[DONE ] {outfile} "
            f"(levels={idx.size} method={method} range=[{lower}, {upper}))"
        )
PY
}

echo "============================================================"
echo "Starting curated ocean product aggregation by depth bins"
echo "IN ROOT         : ${IN_ROOT}"
echo "OUT ROOT        : ${OUT_ROOT}"
echo "TMP DIR         : ${TMP_DIR}"
echo "BIN SET         : ${BIN_SET}"
echo "COPY 2D FILES   : ${COPY_2D_FILES}"
echo "OVERWRITE       : ${OVERWRITE}"
echo "PARALLEL FILES  : ${NPROC}"
echo "============================================================"

mapfile -t files < <(find "${IN_ROOT}" -type f -name "*.nc" | sort)
if (( ${#files[@]} == 0 )); then
  echo "ERROR: No NetCDF files found under: ${IN_ROOT}"
  exit 1
fi

export IN_ROOT OUT_ROOT TMP_DIR BIN_SET COPY_2D_FILES OVERWRITE
export -f process_one_file

printf '%s\0' "${files[@]}" \
  | xargs -0 -n 1 -P "${NPROC}" bash -c 'process_one_file "$1"' _

echo
echo "All depth-bin aggregations completed."
