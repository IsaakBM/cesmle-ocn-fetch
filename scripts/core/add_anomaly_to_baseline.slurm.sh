#!/usr/bin/env bash
# ==============================================================================
#  Generic baseline + anomaly adder
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
#    - Dynamically fill missing top anomaly layers using the first deeper layer
#      that contains valid values
#    - Add the filled anomaly to the baseline
#    - Write the native-resolution output
#    - Optionally regrid the downscaled output to a second target grid
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=add_anom
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=256G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/add_anom_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/add_anom_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
export OMP_NUM_THREADS=1

# ==============================================================================
# Required env vars
#   DATASET_LABEL      : label for logs and default names
#   VAR                : variable label for logs
#   BASELINE_FILE      : baseline climatology file
#   ANOMALY_FILE       : anomaly/delta file
#   OUT_DIR            : directory for native downscaled output
#
# Optional env vars
#   TMP_DIR            : temp directory (default: <OUT_DIR>/tmp_add)
#   OUT_PREFIX         : output prefix (default: <DATASET_LABEL>_<VAR>)
#   FUTURE_TAG         : future window tag (default: future)
#   OUT_SUFFIX         : native output suffix (default: downscaled)
#   WRITE_NATIVE_OUTPUT: yes | no (default: yes)
#   FILL_TOP_MISSING   : yes | no (default: yes)
#   WRITE_FILLED_ANOM  : yes | no (default: no)
#   FILLED_ANOM_DIR    : output dir for debug filled anomalies
#   REGRID_OUTPUT      : yes | no (default: no)
#   REGRID_METHOD      : CDO method for output regrid (default: remapdis)
#   REGRID_GRIDFILE    : target grid file when REGRID_OUTPUT=yes
#   REGRID_OUT_DIR     : output dir for regridded products
#   REGRID_SUFFIX      : suffix for regridded products
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
WRITE_NATIVE_OUTPUT="${WRITE_NATIVE_OUTPUT:-yes}"
FILL_TOP_MISSING="${FILL_TOP_MISSING:-yes}"
WRITE_FILLED_ANOM="${WRITE_FILLED_ANOM:-no}"
FILLED_ANOM_DIR="${FILLED_ANOM_DIR:-}"
REGRID_OUTPUT="${REGRID_OUTPUT:-no}"
REGRID_METHOD="${REGRID_METHOD:-remapdis}"
REGRID_GRIDFILE="${REGRID_GRIDFILE:-}"
REGRID_OUT_DIR="${REGRID_OUT_DIR:-}"
REGRID_SUFFIX="${REGRID_SUFFIX:-}"

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

if [[ "$WRITE_NATIVE_OUTPUT" != "yes" && "$WRITE_NATIVE_OUTPUT" != "no" ]]; then
  echo "ERROR: WRITE_NATIVE_OUTPUT must be yes or no"
  exit 1
fi

if [[ "$FILL_TOP_MISSING" != "yes" && "$FILL_TOP_MISSING" != "no" ]]; then
  echo "ERROR: FILL_TOP_MISSING must be yes or no"
  exit 1
fi

if [[ "$WRITE_FILLED_ANOM" != "yes" && "$WRITE_FILLED_ANOM" != "no" ]]; then
  echo "ERROR: WRITE_FILLED_ANOM must be yes or no"
  exit 1
fi

if [[ "$REGRID_OUTPUT" != "yes" && "$REGRID_OUTPUT" != "no" ]]; then
  echo "ERROR: REGRID_OUTPUT must be yes or no"
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

NATIVE_FILE="${OUT_DIR}/${OUT_PREFIX}_${OUT_SUFFIX}_${FUTURE_TAG}.nc"
TMP_NATIVE="${TMP_DIR}/${OUT_PREFIX}_${OUT_SUFFIX}_${FUTURE_TAG}.tmp.nc"

if [[ "$WRITE_FILLED_ANOM" == "yes" ]]; then
  FILLED_ANOM_FILE="${FILLED_ANOM_DIR}/${OUT_PREFIX}_filled_anomaly_${FUTURE_TAG}.nc"
else
  FILLED_ANOM_FILE=""
fi

if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  REGRID_FILE="${REGRID_OUT_DIR}/${OUT_PREFIX}_${OUT_SUFFIX}_${FUTURE_TAG}_${REGRID_SUFFIX}.nc"
  TMP_REGRID="${TMP_DIR}/${OUT_PREFIX}_${OUT_SUFFIX}_${FUTURE_TAG}_${REGRID_SUFFIX}.tmp.nc"
fi

echo "============================================================"
echo "Starting generic baseline + anomaly addition"
echo "DATASET LABEL      : ${DATASET_LABEL}"
echo "VAR                : ${VAR}"
echo "BASELINE FILE      : ${BASELINE_FILE}"
echo "ANOMALY FILE       : ${ANOMALY_FILE}"
echo "OUT DIR            : ${OUT_DIR}"
echo "TMP DIR            : ${TMP_DIR}"
echo "OUT PREFIX         : ${OUT_PREFIX}"
echo "FUTURE TAG         : ${FUTURE_TAG}"
echo "OUT SUFFIX         : ${OUT_SUFFIX}"
echo "WRITE NATIVE       : ${WRITE_NATIVE_OUTPUT}"
echo "FILL TOP MISSING   : ${FILL_TOP_MISSING}"
echo "WRITE FILLED ANOM  : ${WRITE_FILLED_ANOM}"
if [[ "$WRITE_FILLED_ANOM" == "yes" ]]; then
  echo "FILLED ANOM DIR    : ${FILLED_ANOM_DIR}"
fi
echo "REGRID OUTPUT      : ${REGRID_OUTPUT}"
if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  echo "REGRID METHOD      : ${REGRID_METHOD}"
  echo "REGRID GRIDFILE    : ${REGRID_GRIDFILE}"
  echo "REGRID OUT DIR     : ${REGRID_OUT_DIR}"
  echo "REGRID SUFFIX      : ${REGRID_SUFFIX}"
fi
echo "============================================================"

echo "[STEP1] Removing old outputs if present"
rm -f "${TMP_NATIVE}" "${NATIVE_FILE}"
if [[ "$WRITE_FILLED_ANOM" == "yes" ]]; then
  rm -f "${FILLED_ANOM_FILE}"
fi
if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  rm -f "${TMP_REGRID}" "${REGRID_FILE}"
fi

echo "[STEP2] Filling top missing anomaly layers dynamically and adding to baseline"
python3 - <<PY
import numpy as np
import xarray as xr

baseline_file = "${BASELINE_FILE}"
anomaly_file = "${ANOMALY_FILE}"
tmp_native = "${TMP_NATIVE}"
write_native = "${WRITE_NATIVE_OUTPUT}" == "yes"
fill_top_missing = "${FILL_TOP_MISSING}" == "yes"
write_filled_anom = "${WRITE_FILLED_ANOM}" == "yes"
filled_anom_file = "${FILLED_ANOM_FILE}"

ds_base = xr.open_dataset(baseline_file)
ds_anom = xr.open_dataset(anomaly_file)

def pick_main_var(ds):
    candidates = [
        v for v in ds.data_vars
        if "bnds" not in v.lower() and "bounds" not in v.lower()
    ]
    if not candidates:
        raise ValueError(f"No valid data variable found in dataset: {list(ds.data_vars)}")
    return candidates[0]

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

zdim_candidates = [d for d in da_anom.dims if d.lower() in zdim_names]
if not zdim_candidates:
    raise ValueError(f"Could not identify vertical dimension in anomaly dims: {da_anom.dims}")
zdim = zdim_candidates[0]

da_anom_filled = da_anom.copy()
filled_top_count = 0
first_valid_index = None

if fill_top_missing:
    reduce_dims = [d for d in da_anom.dims if d != zdim]
    if not reduce_dims:
        raise ValueError(f"Anomaly must have dimensions beyond vertical dim {zdim}")

    level_all_nan = da_anom.isnull().all(dim=reduce_dims).values
    nlev = level_all_nan.shape[0]

    for idx in range(nlev):
        if not bool(level_all_nan[idx]):
            first_valid_index = idx
            break

    if first_valid_index is None:
        raise ValueError("All anomaly levels are missing; cannot fill top layers.")

    if first_valid_index > 0:
        donor = da_anom.isel({zdim: first_valid_index})
        for idx in range(first_valid_index):
            if bool(level_all_nan[idx]):
                da_anom_filled[{zdim: idx}] = donor
                filled_top_count += 1

for dim in da_base.dims:
    if dim in da_anom_filled.dims and dim in da_base.coords:
        da_anom_filled = da_anom_filled.assign_coords({dim: da_base.coords[dim]})

da_out = da_base + da_anom_filled
da_out.name = base_var

ds_out = ds_base.copy()
ds_out[base_var] = da_out

encoding = {base_var: {"zlib": True, "complevel": 1}}

print(f"BASE VAR            : {base_var}")
print(f"ANOM VAR            : {anom_var}")
print(f"VERTICAL DIM        : {zdim}")
print(f"FIRST VALID INDEX   : {first_valid_index}")
print(f"TOP LEVELS FILLED   : {filled_top_count}")

if write_native:
    ds_out.to_netcdf(tmp_native, format="NETCDF4", encoding=encoding)

if write_filled_anom:
    filled_name = f"{anom_var}_filled"
    ds_filled = ds_anom.copy()
    ds_filled[filled_name] = da_anom_filled.rename(filled_name)
    ds_filled.to_netcdf(filled_anom_file, format="NETCDF4")

ds_base.close()
ds_anom.close()
PY

if [[ "$WRITE_NATIVE_OUTPUT" == "yes" ]]; then
  echo "[STEP3] Writing native downscaled output"
  mv -f "${TMP_NATIVE}" "${NATIVE_FILE}"
  echo "[DONE ] ${NATIVE_FILE}"
fi

if [[ "$REGRID_OUTPUT" == "yes" ]]; then
  echo "[STEP4] Regridding downscaled output"
  cdo -L -O ${REGRID_METHOD},"${REGRID_GRIDFILE}" "${NATIVE_FILE}" "${TMP_REGRID}"
  mv -f "${TMP_REGRID}" "${REGRID_FILE}"
  echo "[DONE ] ${REGRID_FILE}"
fi

echo
echo "All baseline + anomaly processing completed for VAR=${VAR}"
