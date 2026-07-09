#!/usr/bin/env bash
# ==============================================================================
#  Derive 0.05-degree hindcast baselines with GLORYS coastline filling
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
#   IN_ROOT                   : hindcast baseline root at 0.25
#                               (default: /home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25)
#   OUT_ROOT                  : derived 0.05 root with GLORYS coastline fill
#                               (default: /home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast)
#   GRIDFILE                  : target 0.05 grid description
#                               (default: /home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt)
#   VARS                      : space-separated variable list
#                               (default: auto-detect all vars under IN_ROOT)
#   METHOD                    : auto | cdo remap operator
#                               (default: auto)
#   AUTO_METHOD_DEFAULT       : remap op for regular lat/lon sources
#                               (default: remapbil)
#   AUTO_METHOD_CURVILINEAR   : remap op for curvilinear/unstructured sources
#                               (default: remapdis)
#   COASTAL_MASK_FILE         : file defining target GLORYS wet mask/coastline
#                               (default: GLORYS thetao 2006-2014 climatology)
#   COASTAL_MASK_VAR          : variable to read from COASTAL_MASK_FILE
#                               (default: thetao)
#   COASTAL_FILL_METHOD       : nearest | distance_weighted
#                               (default: distance_weighted)
#   COASTAL_FILL_MAX_STEPS    : maximum donor search radius in grid cells
#                               (default: 12)
#   COASTAL_FILL_WEIGHT_POWER : inverse-distance weighting exponent
#                               (default: 2.0)
#   COASTAL_FILL_MIN_DONORS   : target donor count for distance-weighted fill
#                               (default: 4)
#   OVERWRITE                 : yes | no
#                               (default: yes)
#   NPROC                     : number of files to process in parallel
#                               (default: SLURM_CPUS_PER_TASK or 4)
#
# Note:
#   Outputs are rewritten as NetCDF4 with zlib compression enabled.
#   File sizes can therefore be much smaller than uncompressed inputs even when
#   the output contains more valid coastal cells.
# ==============================================================================

IN_ROOT="${IN_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast}"
GRIDFILE="${GRIDFILE:-/home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt}"
VARS="${VARS:-}"
METHOD="${METHOD:-auto}"
AUTO_METHOD_DEFAULT="${AUTO_METHOD_DEFAULT:-remapbil}"
AUTO_METHOD_CURVILINEAR="${AUTO_METHOD_CURVILINEAR:-remapdis}"
COASTAL_MASK_FILE="${COASTAL_MASK_FILE:-/home/SB5/glorys12v1_monthly_0p05/thetao/clim_windows/glorys12v1_thetao_clim_2006-2014.nc}"
COASTAL_MASK_VAR="${COASTAL_MASK_VAR:-thetao}"
COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD:-distance_weighted}"
COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS:-12}"
COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER:-2.0}"
COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS:-4}"
OVERWRITE="${OVERWRITE:-yes}"
NPROC="${NPROC:-${SLURM_CPUS_PER_TASK:-4}}"

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ ! -f "${GRIDFILE}" ]]; then
  echo "ERROR: GRIDFILE does not exist: ${GRIDFILE}"
  exit 1
fi

if [[ ! -f "${COASTAL_MASK_FILE}" ]]; then
  echo "ERROR: COASTAL_MASK_FILE does not exist: ${COASTAL_MASK_FILE}"
  exit 1
fi

if [[ "${COASTAL_FILL_METHOD}" != "nearest" && "${COASTAL_FILL_METHOD}" != "distance_weighted" ]]; then
  echo "ERROR: COASTAL_FILL_METHOD must be nearest or distance_weighted"
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
  local rel_path rel_dir out_dir base stem outfile tmp_remap tmp_out method_to_use var

  rel_path="${infile#${IN_ROOT}/}"
  rel_dir="$(dirname "${rel_path}")"
  out_dir="${OUT_ROOT}/${rel_dir}"
  base="$(basename "${infile}")"
  stem="${base%.nc}"
  var="${rel_path%%/*}"
  outfile="${out_dir}/${stem}_grid_0p05_global.nc"
  tmp_remap="${out_dir}/.${stem}_grid_0p05_global.remap.tmp.nc"
  tmp_out="${out_dir}/.${stem}_grid_0p05_global.glorys_coast.tmp.nc"

  mkdir -p "${out_dir}"

  if [[ -f "${outfile}" && "${OVERWRITE}" == "no" ]]; then
    echo "[KEEP] ${outfile}"
    return 0
  fi

  rm -f "${tmp_remap}" "${tmp_out}" "${outfile}"

  method_to_use="$(resolve_method "${infile}")"
  echo
  echo "[START] ${rel_path}"
  echo "[INFO ] remap method resolved to: ${method_to_use}"

  /usr/bin/cdo -L -O -P 1 "${method_to_use},${GRIDFILE}" "${infile}" "${tmp_remap}"

  INFILE="${tmp_remap}" \
  OUTFILE="${tmp_out}" \
  VAR="${var}" \
  COASTAL_MASK_FILE="${COASTAL_MASK_FILE}" \
  COASTAL_MASK_VAR="${COASTAL_MASK_VAR}" \
  COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD}" \
  COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS}" \
  COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER}" \
  COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS}" \
  python3 - <<'PY'
import os
import numpy as np
import xarray as xr

infile = os.environ["INFILE"]
outfile = os.environ["OUTFILE"]
var_hint = os.environ["VAR"]
mask_file = os.environ["COASTAL_MASK_FILE"]
mask_var = os.environ["COASTAL_MASK_VAR"]
fill_method = os.environ["COASTAL_FILL_METHOD"]
max_steps = int(os.environ["COASTAL_FILL_MAX_STEPS"])
weight_power = float(os.environ["COASTAL_FILL_WEIGHT_POWER"])
min_donors = int(os.environ["COASTAL_FILL_MIN_DONORS"])

def pick_main_var(ds, requested=None):
    if requested and requested in ds.data_vars:
        return requested
    candidates = [
        v for v in ds.data_vars
        if "bnds" not in v.lower() and "bounds" not in v.lower()
    ]
    if not candidates:
        raise ValueError(f"No valid data variable found in dataset: {list(ds.data_vars)}")
    return candidates[0]

def infer_xy_dims(da):
    preferred = [
        ("lat", "lon"),
        ("latitude", "longitude"),
        ("y", "x"),
    ]
    dims_lower = {d.lower(): d for d in da.dims}
    for y_name, x_name in preferred:
        if y_name in dims_lower and x_name in dims_lower:
            return dims_lower[y_name], dims_lower[x_name]
    if da.ndim < 2:
        raise ValueError(f"Expected at least two dims to infer horizontal axes: {da.dims}")
    return da.dims[-2], da.dims[-1]

def align_to_base_dims(da, da_base, label):
    aligned = da.copy()
    extra_dims = [d for d in aligned.dims if d not in da_base.dims]
    for dim in extra_dims:
        if aligned.sizes.get(dim) == 1:
            aligned = aligned.isel({dim: 0}, drop=True)
        else:
            # Collapse mask-only dimensions, such as GLORYS depth for a 2-D
            # target variable, into one wet mask. True values remain finite;
            # false values are converted to NaN below.
            aligned = aligned.notnull().any(dim=dim)
            aligned = aligned.where(aligned)

    for dim in da_base.dims:
        if dim in aligned.dims and dim in da_base.coords:
            aligned = aligned.assign_coords({dim: da_base.coords[dim]})
        elif dim not in aligned.dims:
            coord = da_base.coords[dim] if dim in da_base.coords else np.arange(da_base.sizes[dim])
            aligned = aligned.expand_dims({dim: coord})

    return aligned.transpose(*da_base.dims)

def build_fill_geometry(max_steps, weight_power):
    offsets = []
    max_radius = max(1, int(max_steps))
    for dy in range(-max_radius, max_radius + 1):
        for dx in range(-max_radius, max_radius + 1):
            if dy == 0 and dx == 0:
                continue
            radius = max(abs(dy), abs(dx))
            if radius > max_radius:
                continue
            dist = float(np.hypot(dy, dx))
            offsets.append((radius, dist, dy, dx))

    offsets.sort(key=lambda item: (item[0], item[1]))

    radii = np.array([item[0] for item in offsets], dtype=np.int16)
    dy = np.array([item[2] for item in offsets], dtype=np.int16)
    dx = np.array([item[3] for item in offsets], dtype=np.int16)
    dist = np.array([item[1] for item in offsets], dtype=float)
    weights = 1.0 / np.power(dist, float(weight_power))

    radius_cutoffs = np.zeros(max_radius + 1, dtype=np.int32)
    for radius in range(1, max_radius + 1):
        radius_cutoffs[radius] = int(np.searchsorted(radii, radius, side="right"))

    return {
        "max_radius": max_radius,
        "dy": dy,
        "dx": dx,
        "weights": weights,
        "radius_cutoffs": radius_cutoffs,
    }

def fill_slice_nearest(data2d, wet2d, geometry):
    filled = np.array(data2d, dtype=float, copy=True)
    source = np.array(data2d, dtype=float, copy=True)
    wet = np.array(wet2d, dtype=bool, copy=False)
    pending_idx = np.argwhere(wet & ~np.isfinite(filled))
    if pending_idx.size == 0:
        return filled, 0

    max_radius = geometry["max_radius"]
    dy = geometry["dy"]
    dx = geometry["dx"]
    radius_cutoffs = geometry["radius_cutoffs"]

    padded_vals = np.pad(source, max_radius, mode="constant", constant_values=np.nan)
    padded_wet = np.pad(wet, max_radius, mode="constant", constant_values=False)
    filled_count = 0

    for iy, ix in pending_idx:
        py = iy + max_radius
        px = ix + max_radius
        for radius in range(1, max_radius + 1):
            end = radius_cutoffs[radius]
            neigh_y = py + dy[:end]
            neigh_x = px + dx[:end]
            valid = padded_wet[neigh_y, neigh_x] & np.isfinite(padded_vals[neigh_y, neigh_x])
            if not np.any(valid):
                continue
            first = int(np.flatnonzero(valid)[0])
            filled[iy, ix] = float(padded_vals[neigh_y[first], neigh_x[first]])
            filled_count += 1
            break

    return filled, filled_count

def fill_slice_distance_weighted(data2d, wet2d, geometry, min_donors):
    filled = np.array(data2d, dtype=float, copy=True)
    source = np.array(data2d, dtype=float, copy=True)
    wet = np.array(wet2d, dtype=bool, copy=False)
    pending_idx = np.argwhere(wet & ~np.isfinite(filled))
    if pending_idx.size == 0:
        return filled, 0

    max_radius = geometry["max_radius"]
    dy = geometry["dy"]
    dx = geometry["dx"]
    weights = geometry["weights"]
    radius_cutoffs = geometry["radius_cutoffs"]

    if not np.any(wet & np.isfinite(source)):
        return filled, 0

    target_donors = max(1, min_donors)
    filled_count = 0
    padded_vals = np.pad(source, max_radius, mode="constant", constant_values=np.nan)
    padded_wet = np.pad(wet, max_radius, mode="constant", constant_values=False)

    for iy, ix in pending_idx:
        py = iy + max_radius
        px = ix + max_radius
        donor_mask = None
        chosen_end = 0

        for radius in range(1, max_radius + 1):
            end = radius_cutoffs[radius]
            neigh_y = py + dy[:end]
            neigh_x = px + dx[:end]
            valid = padded_wet[neigh_y, neigh_x] & np.isfinite(padded_vals[neigh_y, neigh_x])
            donor_count = int(valid.sum())
            if donor_count >= target_donors:
                donor_mask = valid
                chosen_end = end
                break
            if donor_mask is None and donor_count > 0:
                donor_mask = valid
                chosen_end = end

        if donor_mask is None or not np.any(donor_mask):
            continue

        neigh_y = py + dy[:chosen_end]
        neigh_x = px + dx[:chosen_end]
        donor_vals = padded_vals[neigh_y, neigh_x][donor_mask]
        donor_weights = weights[:chosen_end][donor_mask]
        weight_sum = donor_weights.sum()
        if not np.isfinite(weight_sum) or weight_sum <= 0.0:
            continue

        filled[iy, ix] = float(np.sum(donor_weights * donor_vals) / weight_sum)
        filled_count += 1

    return filled, filled_count

ds_base = xr.open_dataset(infile)
ds_mask = xr.open_dataset(mask_file)
try:
    base_var = pick_main_var(ds_base, var_hint)
    da_base = ds_base[base_var]
    da_mask = align_to_base_dims(ds_mask[pick_main_var(ds_mask, mask_var)], da_base, "coastal mask")

    xy_dims = infer_xy_dims(da_base)
    other_dims = [d for d in da_base.dims if d not in xy_dims]

    trans_base = da_base.transpose(*other_dims, *xy_dims)
    trans_mask = da_mask.transpose(*other_dims, *xy_dims)
    base_arr = np.array(trans_base.values, dtype=float, copy=True)
    mask_arr = np.array(trans_mask.values, copy=False)

    flat_base = base_arr.reshape((-1,) + base_arr.shape[-2:])
    flat_mask = mask_arr.reshape((-1,) + mask_arr.shape[-2:])
    geometry = build_fill_geometry(max_steps, weight_power)

    filled_count = 0
    for idx in range(flat_base.shape[0]):
        wet_mask = np.isfinite(flat_mask[idx])
        if fill_method == "nearest":
            filled_slice, added = fill_slice_nearest(flat_base[idx], wet_mask, geometry)
        else:
            filled_slice, added = fill_slice_distance_weighted(
                flat_base[idx], wet_mask, geometry, min_donors
            )
        flat_base[idx] = filled_slice
        filled_count += added

    da_filled = xr.DataArray(
        flat_base.reshape(base_arr.shape),
        coords=trans_base.coords,
        dims=trans_base.dims,
        attrs=da_base.attrs,
        name=da_base.name,
    ).transpose(*da_base.dims)

    ds_out = ds_base.copy()
    ds_out[base_var] = da_filled

    # FLAG: this rewrite intentionally enables NetCDF4 zlib compression.
    # Do not compare old/new file sizes as a data-coverage check; compare
    # valid/missing cell counts instead.
    encoding = {base_var: {"zlib": True, "complevel": 1}}
    ds_out.to_netcdf(outfile, format="NETCDF4", encoding=encoding)

    print(f"BASE VAR              : {base_var}")
    print(f"COASTAL MASK FILE     : {mask_file}")
    print(f"COASTAL MASK VAR      : {mask_var}")
    print(f"BASELINE CELLS FILLED : {filled_count}")
finally:
    ds_base.close()
    ds_mask.close()
PY

  mv -f "${tmp_out}" "${outfile}"
  rm -f "${tmp_remap}"
  echo "[DONE ] ${outfile}"
}

export IN_ROOT OUT_ROOT GRIDFILE METHOD AUTO_METHOD_DEFAULT AUTO_METHOD_CURVILINEAR
export COASTAL_MASK_FILE COASTAL_MASK_VAR COASTAL_FILL_METHOD
export COASTAL_FILL_MAX_STEPS COASTAL_FILL_WEIGHT_POWER COASTAL_FILL_MIN_DONORS OVERWRITE
export -f detect_gridtype resolve_method process_file

echo "============================================================"
echo "Deriving hindcast baselines at 0.05 with GLORYS coast"
echo "IN ROOT          : ${IN_ROOT}"
echo "OUT ROOT         : ${OUT_ROOT}"
echo "GRIDFILE         : ${GRIDFILE}"
echo "METHOD           : ${METHOD}"
if [[ "${METHOD}" == "auto" ]]; then
  echo "AUTO regular     : ${AUTO_METHOD_DEFAULT}"
  echo "AUTO curvilinear : ${AUTO_METHOD_CURVILINEAR}"
fi
echo "COASTAL MASK     : ${COASTAL_MASK_FILE}"
echo "COASTAL MASK VAR : ${COASTAL_MASK_VAR}"
echo "FILL METHOD      : ${COASTAL_FILL_METHOD}"
echo "FILL STEPS       : ${COASTAL_FILL_MAX_STEPS}"
echo "FILL POWER       : ${COASTAL_FILL_WEIGHT_POWER}"
echo "FILL DONORS      : ${COASTAL_FILL_MIN_DONORS}"
echo "OVERWRITE        : ${OVERWRITE}"
echo "PARALLEL FILES   : ${NPROC}"
echo "============================================================"

if [[ -z "${VARS}" ]]; then
  mapfile -t VAR_LIST < <(
    find "${IN_ROOT}" -mindepth 1 -maxdepth 1 -type d \
      | while read -r d; do
          if [[ -d "${d}/clim_windows" ]]; then
            basename "${d}"
          fi
        done \
      | sort
  )
  if (( ${#VAR_LIST[@]} == 0 )); then
    echo "ERROR: No variable directories found under: ${IN_ROOT}"
    exit 1
  fi
  echo "VARS (auto-detected): ${VAR_LIST[*]}"
else
  read -r -a VAR_LIST <<< "${VARS}"
  echo "VARS             : ${VAR_LIST[*]}"
fi

for var in "${VAR_LIST[@]}"; do
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
  printf '%s\0' "${files[@]}" \
    | xargs -0 -n 1 -P "${NPROC}" bash -c 'process_file "$1"' _
done

echo
echo "Finished deriving hindcast baselines at 0.05 with GLORYS coast."
