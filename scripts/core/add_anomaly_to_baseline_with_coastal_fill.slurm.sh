#!/usr/bin/env bash
# ==============================================================================
#  Baseline + anomaly adder with coastal gap fill on the target baseline grid
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read one baseline climatology file and one anomaly/delta file
#    - Optionally remap the anomaly to the baseline target grid
#    - Fill coastal anomaly gaps on the trusted baseline wet mask
#    - Add the filled anomaly to the baseline
#    - Dynamically fill missing top layers in the final output
#    - Write the native target-grid output
#    - Optionally regrid the final downscaled output to a second grid
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=add_anom_cf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=256G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/add_anom_cf_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/add_anom_cf_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
export OMP_NUM_THREADS=1

# ==============================================================================
# Required env vars
#   DATASET_LABEL             : label for logs and default names
#   VAR                       : variable label for logs
#   BASELINE_FILE             : baseline climatology file on the trusted target grid
#   ANOMALY_FILE              : anomaly/delta file
#   OUT_DIR                   : directory for native downscaled output
#
# Optional env vars
#   TMP_DIR                   : temp directory (default: <OUT_DIR>/tmp_add)
#   OUT_PREFIX                : output prefix (default: <DATASET_LABEL>_<VAR>)
#   FUTURE_TAG                : future window tag (default: future)
#   OUT_SUFFIX                : native output suffix (default: downscaled)
#   NATIVE_SUFFIX             : optional suffix appended to native output names,
#                               e.g. grid_0p05_global
#   WRITE_NATIVE_OUTPUT       : yes | no (default: yes)
#   FILL_TOP_MISSING          : yes | no (default: yes)
#   WRITE_FILLED_ANOM         : yes | no (default: no)
#   FILLED_ANOM_DIR           : output dir for debug filled anomalies
#   REGRID_OUTPUT             : yes | no (default: no)
#   REGRID_METHOD             : CDO method for output regrid (default: remapdis)
#   REGRID_GRIDFILE           : target grid file when REGRID_OUTPUT=yes
#   REGRID_OUT_DIR            : output dir for regridded products
#   REGRID_SUFFIX             : suffix for regridded products
#   REMAP_ANOMALY_TO_BASELINE : yes | no (default: no)
#   ANOMALY_GRIDFILE          : target grid file used to remap anomaly onto the
#                               baseline grid when REMAP_ANOMALY_TO_BASELINE=yes
#   ANOMALY_REGRID_METHOD     : auto | CDO method for anomaly remap (default: auto)
#   ANOMALY_AUTO_METHOD_DEFAULT
#                             : remap op for regular lon/lat anomaly sources
#                               (default: remapbil)
#   ANOMALY_AUTO_METHOD_CURVILINEAR
#                             : remap op for curvilinear/unstructured anomaly
#                               sources (default: remapdis)
#   COASTAL_FILL              : yes | no (default: yes)
#   COASTAL_FILL_METHOD       : nearest | distance_weighted
#                               (default: distance_weighted)
#   COASTAL_MASK_FILE         : optional file defining wet mask/fill domain.
#                               If unset, baseline finite cells define the mask.
#   COASTAL_MASK_VAR          : optional variable name in COASTAL_MASK_FILE.
#                               If unset, first non-bounds variable is used.
#   FILL_BASELINE_COASTAL_GAPS
#                             : yes | no, fill missing baseline cells inside
#                               the coastal mask before adding anomaly
#                               (default: no)
#   COASTAL_FILL_MAX_STEPS    : maximum neighbor-expansion steps for coastal fill
#                               on the trusted baseline wet mask (default: 12)
#   COASTAL_FILL_WEIGHT_POWER : inverse-distance weighting exponent used when
#                               COASTAL_FILL_METHOD=distance_weighted
#                               (default: 2.0)
#   COASTAL_FILL_MIN_DONORS   : target minimum donor count for
#                               COASTAL_FILL_METHOD=distance_weighted
#                               (default: 4)
# ==============================================================================
DATASET_LABEL="${DATASET_LABEL:-dataset}"
VAR="${VAR:-}"
BASELINE_FILE="${BASELINE_FILE:-}"
ANOMALY_FILE="${ANOMALY_FILE:-}"
OUT_DIR="${OUT_DIR:-}"

TMP_DIR="${TMP_DIR:-}"
OUT_PREFIX="${OUT_PREFIX:-}"
FUTURE_TAG="${FUTURE_TAG:-future}"
OUT_SUFFIX="${OUT_SUFFIX:-downscaled}"
NATIVE_SUFFIX="${NATIVE_SUFFIX:-}"
WRITE_NATIVE_OUTPUT="${WRITE_NATIVE_OUTPUT:-yes}"
FILL_TOP_MISSING="${FILL_TOP_MISSING:-yes}"
WRITE_FILLED_ANOM="${WRITE_FILLED_ANOM:-no}"
FILLED_ANOM_DIR="${FILLED_ANOM_DIR:-}"
REGRID_OUTPUT="${REGRID_OUTPUT:-no}"
REGRID_METHOD="${REGRID_METHOD:-remapdis}"
REGRID_GRIDFILE="${REGRID_GRIDFILE:-}"
REGRID_OUT_DIR="${REGRID_OUT_DIR:-}"
REGRID_SUFFIX="${REGRID_SUFFIX:-}"

REMAP_ANOMALY_TO_BASELINE="${REMAP_ANOMALY_TO_BASELINE:-no}"
ANOMALY_GRIDFILE="${ANOMALY_GRIDFILE:-}"
ANOMALY_REGRID_METHOD="${ANOMALY_REGRID_METHOD:-auto}"
ANOMALY_AUTO_METHOD_DEFAULT="${ANOMALY_AUTO_METHOD_DEFAULT:-remapbil}"
ANOMALY_AUTO_METHOD_CURVILINEAR="${ANOMALY_AUTO_METHOD_CURVILINEAR:-remapdis}"
COASTAL_FILL="${COASTAL_FILL:-yes}"
COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD:-distance_weighted}"
COASTAL_MASK_FILE="${COASTAL_MASK_FILE:-}"
COASTAL_MASK_VAR="${COASTAL_MASK_VAR:-}"
FILL_BASELINE_COASTAL_GAPS="${FILL_BASELINE_COASTAL_GAPS:-no}"
COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS:-12}"
COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER:-2.0}"
COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS:-4}"

if [[ -z "$VAR" || -z "$BASELINE_FILE" || -z "$ANOMALY_FILE" || -z "$OUT_DIR" ]]; then
  echo "ERROR: Missing required environment variables."
  echo "Required: VAR, BASELINE_FILE, ANOMALY_FILE, OUT_DIR"
  exit 1
fi

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "ERROR: Baseline file not found: ${BASELINE_FILE}"
  exit 1
fi

if [[ ! -f "$ANOMALY_FILE" ]]; then
  echo "ERROR: Anomaly file not found: ${ANOMALY_FILE}"
  exit 1
fi

for flag_var in WRITE_NATIVE_OUTPUT FILL_TOP_MISSING WRITE_FILLED_ANOM REGRID_OUTPUT REMAP_ANOMALY_TO_BASELINE COASTAL_FILL FILL_BASELINE_COASTAL_GAPS; do
  flag_val="${!flag_var}"
  if [[ "$flag_val" != "yes" && "$flag_val" != "no" ]]; then
    echo "ERROR: ${flag_var} must be yes or no"
    exit 1
  fi
done

if [[ "${COASTAL_FILL_METHOD}" != "nearest" && "${COASTAL_FILL_METHOD}" != "distance_weighted" ]]; then
  echo "ERROR: COASTAL_FILL_METHOD must be nearest or distance_weighted"
  exit 1
fi

if [[ "$REMAP_ANOMALY_TO_BASELINE" == "yes" && ! -f "$ANOMALY_GRIDFILE" ]]; then
  echo "ERROR: ANOMALY_GRIDFILE must exist when REMAP_ANOMALY_TO_BASELINE=yes"
  exit 1
fi

if [[ -n "$COASTAL_MASK_FILE" && ! -f "$COASTAL_MASK_FILE" ]]; then
  echo "ERROR: COASTAL_MASK_FILE does not exist: ${COASTAL_MASK_FILE}"
  exit 1
fi

if [[ "$REGRID_OUTPUT" == "yes" && ! -f "$REGRID_GRIDFILE" ]]; then
  echo "ERROR: REGRID_GRIDFILE must exist when REGRID_OUTPUT=yes"
  exit 1
fi

if [[ -z "$TMP_DIR" ]]; then
  TMP_DIR="${OUT_DIR}/tmp_add"
fi

if [[ -z "$OUT_PREFIX" ]]; then
  OUT_PREFIX="${DATASET_LABEL}_${VAR}"
fi

if [[ "$WRITE_FILLED_ANOM" == "yes" && -z "$FILLED_ANOM_DIR" ]]; then
  FILLED_ANOM_DIR="${OUT_DIR}/filled_anomaly"
fi

if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  if [[ -z "$REGRID_OUT_DIR" ]]; then
    REGRID_OUT_DIR="${OUT_DIR}/regridded"
  fi
  if [[ -z "$REGRID_SUFFIX" ]]; then
    REGRID_SUFFIX="$(basename "$REGRID_GRIDFILE" .txt)"
  fi
fi

mkdir -p "${OUT_DIR}" "${TMP_DIR}"
if [[ "$WRITE_FILLED_ANOM" == "yes" ]]; then
  mkdir -p "${FILLED_ANOM_DIR}"
fi
if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  mkdir -p "${REGRID_OUT_DIR}"
fi

NATIVE_NAME="${OUT_PREFIX}_${OUT_SUFFIX}_${FUTURE_TAG}"
if [[ -n "${NATIVE_SUFFIX}" ]]; then
  NATIVE_NAME="${NATIVE_NAME}_${NATIVE_SUFFIX}"
fi

NATIVE_FILE="${OUT_DIR}/${NATIVE_NAME}.nc"
TMP_NATIVE="${TMP_DIR}/${NATIVE_NAME}.tmp.nc"
TMP_ANOM_TARGET="${TMP_DIR}/${OUT_PREFIX}_anomaly_on_target_${FUTURE_TAG}.tmp.nc"

if [[ "$WRITE_FILLED_ANOM" == "yes" ]]; then
  FILLED_ANOM_FILE="${FILLED_ANOM_DIR}/${OUT_PREFIX}_filled_anomaly_${FUTURE_TAG}.nc"
else
  FILLED_ANOM_FILE=""
fi

if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  REGRID_FILE="${REGRID_OUT_DIR}/${OUT_PREFIX}_${OUT_SUFFIX}_${FUTURE_TAG}_${REGRID_SUFFIX}.nc"
  TMP_REGRID="${TMP_DIR}/${OUT_PREFIX}_${OUT_SUFFIX}_${FUTURE_TAG}_${REGRID_SUFFIX}.tmp.nc"
fi

detect_gridtype() {
  local src="$1"
  local gridtype

  gridtype="$(/usr/bin/cdo -s griddes "$src" 2>/dev/null | awk '$1 == "gridtype" {print $3; exit}')"
  if [[ -z "$gridtype" ]]; then
    gridtype="unknown"
  fi
  printf '%s\n' "$gridtype"
}

resolve_anomaly_method() {
  local src="$1"
  local gridtype

  if [[ "$ANOMALY_REGRID_METHOD" != "auto" ]]; then
    printf '%s\n' "$ANOMALY_REGRID_METHOD"
    return 0
  fi

  gridtype="$(detect_gridtype "$src")"
  case "$gridtype" in
    curvilinear|unstructured)
      printf '%s\n' "$ANOMALY_AUTO_METHOD_CURVILINEAR"
      ;;
    *)
      printf '%s\n' "$ANOMALY_AUTO_METHOD_DEFAULT"
      ;;
  esac
}

echo "============================================================"
echo "Starting baseline + anomaly addition with coastal fill"
echo "DATASET LABEL        : ${DATASET_LABEL}"
echo "VAR                  : ${VAR}"
echo "BASELINE FILE        : ${BASELINE_FILE}"
echo "ANOMALY FILE         : ${ANOMALY_FILE}"
echo "OUT DIR              : ${OUT_DIR}"
echo "TMP DIR              : ${TMP_DIR}"
echo "OUT PREFIX           : ${OUT_PREFIX}"
echo "FUTURE TAG           : ${FUTURE_TAG}"
echo "OUT SUFFIX           : ${OUT_SUFFIX}"
echo "NATIVE SUFFIX        : ${NATIVE_SUFFIX:-<none>}"
echo "WRITE NATIVE         : ${WRITE_NATIVE_OUTPUT}"
echo "FILL TOP MISSING     : ${FILL_TOP_MISSING}"
echo "WRITE FILLED ANOM    : ${WRITE_FILLED_ANOM}"
echo "REMAP ANOM TO TARGET : ${REMAP_ANOMALY_TO_BASELINE}"
echo "COASTAL FILL         : ${COASTAL_FILL}"
echo "COASTAL FILL METHOD  : ${COASTAL_FILL_METHOD}"
echo "COASTAL FILL STEPS   : ${COASTAL_FILL_MAX_STEPS}"
echo "COASTAL FILL POWER   : ${COASTAL_FILL_WEIGHT_POWER}"
echo "COASTAL FILL DONORS  : ${COASTAL_FILL_MIN_DONORS}"
echo "COASTAL MASK FILE    : ${COASTAL_MASK_FILE:-<baseline finite mask>}"
echo "COASTAL MASK VAR     : ${COASTAL_MASK_VAR:-<auto>}"
echo "FILL BASELINE GAPS   : ${FILL_BASELINE_COASTAL_GAPS}"
if [[ "$REMAP_ANOMALY_TO_BASELINE" == "yes" ]]; then
  echo "ANOM GRIDFILE        : ${ANOMALY_GRIDFILE}"
  echo "ANOM REGRID METHOD   : ${ANOMALY_REGRID_METHOD}"
  if [[ "$ANOMALY_REGRID_METHOD" == "auto" ]]; then
    echo "ANOM AUTO REGULAR    : ${ANOMALY_AUTO_METHOD_DEFAULT}"
    echo "ANOM AUTO CURVILIN   : ${ANOMALY_AUTO_METHOD_CURVILINEAR}"
  fi
fi
echo "REGRID OUTPUT        : ${REGRID_OUTPUT}"
if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  echo "FINAL REGRID METHOD  : ${REGRID_METHOD}"
  echo "FINAL REGRID GRID    : ${REGRID_GRIDFILE}"
  echo "FINAL REGRID OUT DIR : ${REGRID_OUT_DIR}"
  echo "FINAL REGRID SUFFIX  : ${REGRID_SUFFIX}"
fi
echo "============================================================"

echo "[STEP1] Removing old outputs if present"
rm -f "${TMP_NATIVE}" "${NATIVE_FILE}" "${TMP_ANOM_TARGET}"
if [[ "$WRITE_FILLED_ANOM" == "yes" ]]; then
  rm -f "${FILLED_ANOM_FILE}"
fi
if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  rm -f "${TMP_REGRID}" "${REGRID_FILE}"
fi

ANOMALY_FOR_PYTHON="${ANOMALY_FILE}"
if [[ "$REMAP_ANOMALY_TO_BASELINE" == "yes" ]]; then
  echo "[STEP2] Remapping anomaly onto the trusted baseline grid"
  anom_method="$(resolve_anomaly_method "${ANOMALY_FILE}")"
  echo "INFO: anomaly remap method resolved to: ${anom_method}"
  cdo -L -O "${anom_method},${ANOMALY_GRIDFILE}" "${ANOMALY_FILE}" "${TMP_ANOM_TARGET}"
  ANOMALY_FOR_PYTHON="${TMP_ANOM_TARGET}"
  echo "[DONE ] ${TMP_ANOM_TARGET}"
fi

echo "[STEP3] Filling coastal anomaly gaps on the target wet mask and adding to baseline"
python3 - <<PY
import numpy as np
import xarray as xr

baseline_file = "${BASELINE_FILE}"
anomaly_file = "${ANOMALY_FOR_PYTHON}"
coastal_mask_file = "${COASTAL_MASK_FILE}"
coastal_mask_var = "${COASTAL_MASK_VAR}"
tmp_native = "${TMP_NATIVE}"
write_native = "${WRITE_NATIVE_OUTPUT}" == "yes"
fill_top_missing = "${FILL_TOP_MISSING}" == "yes"
write_filled_anom = "${WRITE_FILLED_ANOM}" == "yes"
filled_anom_file = "${FILLED_ANOM_FILE}"
coastal_fill = "${COASTAL_FILL}" == "yes"
coastal_fill_method = "${COASTAL_FILL_METHOD}"
fill_baseline_coastal_gaps = "${FILL_BASELINE_COASTAL_GAPS}" == "yes"
coastal_fill_max_steps = int("${COASTAL_FILL_MAX_STEPS}")
coastal_fill_weight_power = float("${COASTAL_FILL_WEIGHT_POWER}")
coastal_fill_min_donors = int("${COASTAL_FILL_MIN_DONORS}")

ds_base = xr.open_dataset(baseline_file)
ds_anom = xr.open_dataset(anomaly_file)
ds_mask = xr.open_dataset(coastal_mask_file) if coastal_mask_file else None

def pick_main_var(ds, requested=None):
    if requested:
        if requested not in ds.data_vars:
            raise ValueError(
                f"Requested variable {requested!r} not found in dataset: {list(ds.data_vars)}"
            )
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
            raise ValueError(
                f"{label} has unsupported dimension {dim!r}; "
                f"expected subset of baseline dims {da_base.dims}"
            )

    for dim in da_base.dims:
        if dim in aligned.dims and dim in da_base.coords:
            aligned = aligned.assign_coords({dim: da_base.coords[dim]})
        elif dim not in aligned.dims:
            coord = da_base.coords[dim] if dim in da_base.coords else np.arange(da_base.sizes[dim])
            aligned = aligned.expand_dims({dim: coord})

    return aligned.transpose(*da_base.dims)

_fill_geometry_cache = {}

def build_fill_geometry(max_steps, weight_power):
    key = (int(max_steps), float(weight_power))
    cached = _fill_geometry_cache.get(key)
    if cached is not None:
        return cached

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

    geometry = {
        "max_radius": max_radius,
        "dy": dy,
        "dx": dx,
        "weights": weights,
        "radius_cutoffs": radius_cutoffs,
    }
    _fill_geometry_cache[key] = geometry
    return geometry

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
        found = False

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
            found = True
            break

        if not found:
            continue

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

base_var = pick_main_var(ds_base)

anom_candidates = [
    v for v in ds_anom.data_vars
    if "bnds" not in v.lower() and "bounds" not in v.lower()
]
if not anom_candidates:
    raise ValueError(f"No valid anomaly variable found in dataset: {list(ds_anom.data_vars)}")

zdim_names = ("depth", "depth_below_sea", "lev", "z_t")
anom_var = None
for v in anom_candidates:
    dims_lower = tuple(d.lower() for d in ds_anom[v].dims)
    if any(z in dims_lower for z in zdim_names):
        anom_var = v
        break
if anom_var is None:
    anom_var = anom_candidates[0]

da_base = ds_base[base_var]
da_anom = ds_anom[anom_var]
da_mask = None
mask_var = None
if ds_mask is not None:
    mask_var = pick_main_var(ds_mask, coastal_mask_var or None)
    da_mask = align_to_base_dims(ds_mask[mask_var], da_base, "coastal mask")

da_anom_aligned = da_anom.copy()
for dim in da_base.dims:
    if dim in da_anom_aligned.dims and dim in da_base.coords:
        da_anom_aligned = da_anom_aligned.assign_coords({dim: da_base.coords[dim]})
da_anom_aligned = da_anom_aligned.transpose(*da_base.dims)

xy_dims = infer_xy_dims(da_base)
other_dims = [d for d in da_base.dims if d not in xy_dims]

coastal_fill_count = 0
baseline_fill_count = 0
da_base_filled = da_base
if coastal_fill:
    trans_base = da_base.transpose(*other_dims, *xy_dims)
    trans_anom = da_anom_aligned.transpose(*other_dims, *xy_dims)
    trans_mask = da_mask.transpose(*other_dims, *xy_dims) if da_mask is not None else None

    base_arr = np.array(trans_base.values, dtype=float, copy=True)
    anom_arr = np.array(trans_anom.values, dtype=float, copy=True)
    mask_arr = np.array(trans_mask.values, copy=False) if trans_mask is not None else None

    flat_base = base_arr.reshape((-1,) + base_arr.shape[-2:])
    flat_anom = anom_arr.reshape((-1,) + anom_arr.shape[-2:])
    flat_mask = (
        mask_arr.reshape((-1,) + mask_arr.shape[-2:])
        if mask_arr is not None
        else None
    )
    fill_geometry = build_fill_geometry(
        coastal_fill_max_steps,
        coastal_fill_weight_power,
    )

    for idx in range(flat_anom.shape[0]):
        if flat_mask is not None:
            wet_mask = np.isfinite(flat_mask[idx])
        else:
            wet_mask = np.isfinite(flat_base[idx])

        if fill_baseline_coastal_gaps:
            if coastal_fill_method == "nearest":
                filled_base_slice, added_base = fill_slice_nearest(
                    flat_base[idx], wet_mask, fill_geometry
                )
            else:
                filled_base_slice, added_base = fill_slice_distance_weighted(
                    flat_base[idx],
                    wet_mask,
                    fill_geometry,
                    coastal_fill_min_donors,
                )
            flat_base[idx] = filled_base_slice
            baseline_fill_count += added_base

        if coastal_fill_method == "nearest":
            filled_slice, added = fill_slice_nearest(
                flat_anom[idx], wet_mask, fill_geometry
            )
        else:
            filled_slice, added = fill_slice_distance_weighted(
                flat_anom[idx],
                wet_mask,
                fill_geometry,
                coastal_fill_min_donors,
            )
        flat_anom[idx] = filled_slice
        coastal_fill_count += added

    da_base_filled = xr.DataArray(
        flat_base.reshape(base_arr.shape),
        coords=trans_base.coords,
        dims=trans_base.dims,
        attrs=da_base.attrs,
        name=da_base.name,
    ).transpose(*da_base.dims)

    da_anom_filled = xr.DataArray(
        flat_anom.reshape(anom_arr.shape),
        coords=trans_anom.coords,
        dims=trans_anom.dims,
        attrs=da_anom_aligned.attrs,
        name=da_anom_aligned.name,
    ).transpose(*da_base.dims)
else:
    da_anom_filled = da_anom_aligned

da_out = da_base_filled + da_anom_filled
da_out.name = base_var

filled_top_count = 0
first_valid_index = None

if fill_top_missing:
    zdim_out_candidates = [d for d in da_out.dims if d.lower() in zdim_names]
    if not zdim_out_candidates:
        raise ValueError(f"Could not identify vertical dimension in output dims: {da_out.dims}")
    zdim_out = zdim_out_candidates[0]

    other_dims_out = [d for d in da_out.dims if d != zdim_out]
    if not other_dims_out:
        raise ValueError(f"Output must have dimensions beyond vertical dim {zdim_out}")

    transposed = da_out.transpose(zdim_out, *other_dims_out)
    arr = transposed.values
    nlev = arr.shape[0]
    flat = arr.reshape(nlev, -1)

    first_valid_indices = np.full(flat.shape[1], -1, dtype=int)

    for col in range(flat.shape[1]):
        valid = np.where(np.isfinite(flat[:, col]))[0]
        if valid.size > 0:
            first_valid_indices[col] = int(valid[0])

    for col in range(flat.shape[1]):
        donor_idx = first_valid_indices[col]
        if donor_idx <= 0:
            continue
        donor_val = flat[donor_idx, col]
        for idx in range(donor_idx):
            if not np.isfinite(flat[idx, col]):
                flat[idx, col] = donor_val
                filled_top_count += 1

    filled_arr = flat.reshape(arr.shape)
    da_out = xr.DataArray(
        filled_arr,
        coords=transposed.coords,
        dims=transposed.dims,
        attrs=da_out.attrs,
        name=da_out.name,
    ).transpose(*da_base.dims)

    valid_indices = first_valid_indices[first_valid_indices >= 0]
    if valid_indices.size > 0:
        first_valid_index = int(valid_indices.min())

ds_out = ds_base.copy()
ds_out[base_var] = da_out

# FLAG: the final native downscaled output is intentionally rewritten as
# NetCDF4 with zlib compression. Old/new file sizes are not a reliable
# coverage check; compare valid/missing cell counts instead.
encoding = {base_var: {"zlib": True, "complevel": 1}}

print(f"BASE VAR              : {base_var}")
print(f"ANOM VAR              : {anom_var}")
print(f"COASTAL MASK FILE     : {coastal_mask_file or '<baseline finite mask>'}")
print(f"COASTAL MASK VAR      : {mask_var or '<none>'}")
print(f"COASTAL FILL ENABLED  : {coastal_fill}")
print(f"COASTAL FILL METHOD   : {coastal_fill_method}")
print(f"BASELINE CELLS FILLED : {baseline_fill_count}")
print(f"ANOMALY CELLS FILLED  : {coastal_fill_count}")
print(f"FIRST VALID INDEX     : {first_valid_index}")
print(f"TOP LEVELS FILLED     : {filled_top_count}")

if write_native:
    ds_out.to_netcdf(tmp_native, format="NETCDF4", encoding=encoding)

if write_filled_anom:
    filled_name = f"{anom_var}_filled"
    ds_filled = ds_anom.copy()
    ds_filled[filled_name] = da_anom_filled.rename(filled_name)
    ds_filled.to_netcdf(filled_anom_file, format="NETCDF4")

ds_base.close()
ds_anom.close()
if ds_mask is not None:
    ds_mask.close()
PY

if [[ "$WRITE_NATIVE_OUTPUT" == "yes" ]]; then
  echo "[STEP4] Writing native downscaled output"
  mv -f "${TMP_NATIVE}" "${NATIVE_FILE}"
  echo "[DONE ] ${NATIVE_FILE}"
fi

if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  echo "[STEP5] Regridding final downscaled output"
  cdo -L -O "${REGRID_METHOD},${REGRID_GRIDFILE}" "${NATIVE_FILE}" "${TMP_REGRID}"
  mv -f "${TMP_REGRID}" "${REGRID_FILE}"
  echo "[DONE ] ${REGRID_FILE}"
fi

echo
echo "All baseline + anomaly processing with coastal fill completed for VAR=${VAR}"
