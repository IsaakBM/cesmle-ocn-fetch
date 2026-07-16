#!/usr/bin/env bash
# ==============================================================================
#  Generic delta builder from climatology files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read one baseline climatology file and one future climatology file
#    - Compute future minus baseline delta
#    - Optionally regrid the resulting delta to a target lon/lat grid
#    - Write one delta product per baseline/future file pair
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=delta_clim
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/delta_clim_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/delta_clim_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail

# ==============================================================================
# Required env vars (passed at sbatch time)
#   DATASET_LABEL   : short dataset label for logs/messages
#   VAR             : variable to process
#   BASELINE_FILE   : baseline climatology file
#   FUTURE_FILE     : future climatology file
#   OUT_DIR         : directory where delta outputs will be written
#
# Optional env vars
#   TMP_DIR           : temp directory (default: <OUT_DIR>/tmp_delta)
#   FUTURE_TAG        : label for the future window (default: future)
#   BASELINE_TAG      : label for the baseline window (default: baseline)
#   OUT_PREFIX        : output prefix (default: <DATASET_LABEL>_<VAR>)
#   DELTA_MODE        : additive | log_ratio (default: additive)
#   REGRID_DELTA      : yes | no (default: no)
#   GRIDFILE          : target grid file when REGRID_DELTA=yes
#   METHOD            : CDO remapping method (default: remapbil)
#   REGRID_OUT_DIR    : output dir for regridded deltas
#                       (default: <OUT_DIR>/regridded)
#   REGRID_SUFFIX     : suffix for regridded deltas
#                       (default: <gridfile basename>)
# ==============================================================================
DATASET_LABEL="${DATASET_LABEL:-dataset}"
VAR="${VAR:-}"
BASELINE_FILE="${BASELINE_FILE:-}"
FUTURE_FILE="${FUTURE_FILE:-}"
OUT_DIR="${OUT_DIR:-}"

TMP_DIR="${TMP_DIR:-}"
FUTURE_TAG="${FUTURE_TAG:-future}"
BASELINE_TAG="${BASELINE_TAG:-baseline}"
OUT_PREFIX="${OUT_PREFIX:-}"
DELTA_MODE="${DELTA_MODE:-additive}"
REGRID_DELTA="${REGRID_DELTA:-no}"
GRIDFILE="${GRIDFILE:-}"
METHOD="${METHOD:-remapbil}"
REGRID_OUT_DIR="${REGRID_OUT_DIR:-}"
REGRID_SUFFIX="${REGRID_SUFFIX:-}"

if [[ -z "$VAR" || -z "$BASELINE_FILE" || -z "$FUTURE_FILE" || -z "$OUT_DIR" ]]; then
  echo "ERROR: Missing required environment variables."
  echo "Required: VAR, BASELINE_FILE, FUTURE_FILE, OUT_DIR"
  echo "Optional: DATASET_LABEL, TMP_DIR, FUTURE_TAG, BASELINE_TAG, OUT_PREFIX, DELTA_MODE, REGRID_DELTA, GRIDFILE, METHOD, REGRID_OUT_DIR, REGRID_SUFFIX"
  exit 1
fi

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "ERROR: Baseline file not found: ${BASELINE_FILE}"
  exit 1
fi

if [[ ! -f "$FUTURE_FILE" ]]; then
  echo "ERROR: Future file not found: ${FUTURE_FILE}"
  exit 1
fi

if [[ "$REGRID_DELTA" != "yes" && "$REGRID_DELTA" != "no" ]]; then
  echo "ERROR: REGRID_DELTA must be one of: yes, no"
  exit 1
fi

if [[ "$DELTA_MODE" != "additive" && "$DELTA_MODE" != "log_ratio" ]]; then
  echo "ERROR: DELTA_MODE must be one of: additive, log_ratio"
  exit 1
fi

if [[ "$REGRID_DELTA" == "yes" && ! -f "$GRIDFILE" ]]; then
  echo "ERROR: GRIDFILE must exist when REGRID_DELTA=yes"
  exit 1
fi

if [[ -z "$TMP_DIR" ]]; then
  TMP_DIR="${OUT_DIR}/tmp_delta"
fi

if [[ -z "$OUT_PREFIX" ]]; then
  OUT_PREFIX="${DATASET_LABEL}_${VAR}"
fi

if [[ "$REGRID_DELTA" == "yes" ]]; then
  if [[ -z "$REGRID_OUT_DIR" ]]; then
    REGRID_OUT_DIR="${OUT_DIR}/regridded"
  fi
  if [[ -z "$REGRID_SUFFIX" ]]; then
    REGRID_SUFFIX="$(basename "$GRIDFILE" .txt)"
  fi
fi

mkdir -p "${OUT_DIR}" "${TMP_DIR}"
if [[ "$REGRID_DELTA" == "yes" ]]; then
  mkdir -p "${REGRID_OUT_DIR}"
fi

echo "============================================================"
echo "Starting climatology delta processing"
echo "DATASET LABEL   : ${DATASET_LABEL}"
echo "VAR             : ${VAR}"
echo "BASELINE FILE   : ${BASELINE_FILE}"
echo "FUTURE FILE     : ${FUTURE_FILE}"
echo "OUT DIR         : ${OUT_DIR}"
echo "TMP DIR         : ${TMP_DIR}"
echo "BASELINE TAG    : ${BASELINE_TAG}"
echo "FUTURE TAG      : ${FUTURE_TAG}"
echo "OUT PREFIX      : ${OUT_PREFIX}"
echo "DELTA MODE      : ${DELTA_MODE}"
echo "REGRID DELTA    : ${REGRID_DELTA}"
if [[ "$REGRID_DELTA" == "yes" ]]; then
  echo "GRIDFILE        : ${GRIDFILE}"
  echo "METHOD          : ${METHOD}"
  echo "REGRID OUT DIR  : ${REGRID_OUT_DIR}"
  echo "REGRID SUFFIX   : ${REGRID_SUFFIX}"
fi
echo "============================================================"

DELTA_FILE="${OUT_DIR}/${OUT_PREFIX}_delta_${FUTURE_TAG}_minus_${BASELINE_TAG}.nc"
TMP_DELTA="${TMP_DIR}/${OUT_PREFIX}_delta_${FUTURE_TAG}_minus_${BASELINE_TAG}.tmp.nc"

echo "[STEP1] Removing old outputs if present"
rm -f "${DELTA_FILE}" "${TMP_DELTA}"

echo "[STEP2] Computing delta with mode: ${DELTA_MODE}"
if [[ "$DELTA_MODE" == "additive" ]]; then
  cdo -L -O sub "${FUTURE_FILE}" "${BASELINE_FILE}" "${TMP_DELTA}"
else
  python3 - <<PY
import numpy as np
import xarray as xr

baseline_file = "${BASELINE_FILE}"
future_file = "${FUTURE_FILE}"
tmp_delta = "${TMP_DELTA}"
requested_var = "${VAR}"
delta_mode = "${DELTA_MODE}"

def pick_main_var(ds, requested=None):
    if requested and requested in ds.data_vars:
        return requested
    candidates = [
        name for name in ds.data_vars
        if "bnds" not in name.lower() and "bounds" not in name.lower()
    ]
    if not candidates:
        raise ValueError(f"No valid data variable found in dataset: {list(ds.data_vars)}")
    return candidates[0]

with xr.open_dataset(baseline_file) as ds_base, xr.open_dataset(future_file) as ds_future:
    base_var = pick_main_var(ds_base, requested_var)
    future_var = pick_main_var(ds_future, requested_var)
    if base_var != future_var:
        raise ValueError(f"Baseline/future variable mismatch: {base_var} vs {future_var}")

    da_base = ds_base[base_var]
    da_future = ds_future[future_var]
    if set(da_base.dims) != set(da_future.dims):
        raise ValueError(
            f"Baseline/future dimensions differ: {da_base.dims} vs {da_future.dims}"
        )
    da_base = da_base.transpose(*da_future.dims)
    if da_base.shape != da_future.shape:
        raise ValueError(
            f"Baseline/future shapes differ after transpose: {da_base.shape} vs {da_future.shape}"
        )

    future_values = np.asarray(da_future.values, dtype=float)
    base_values = np.asarray(da_base.values, dtype=float)
    valid = (
        np.isfinite(future_values)
        & np.isfinite(base_values)
        & (future_values > 0)
        & (base_values > 0)
    )
    delta_values = np.full(future_values.shape, np.nan, dtype=float)
    delta_values[valid] = np.log(future_values[valid]) - np.log(base_values[valid])
    da_delta = xr.DataArray(
        delta_values,
        coords=da_future.coords,
        dims=da_future.dims,
        name=future_var,
    )
    da_delta.attrs = da_future.attrs.copy()
    da_delta.attrs.update({
        "delta_mode": delta_mode,
        "delta_formula": "log(future) - log(baseline)",
        "invalid_log_ratio_policy": "missing where future <= 0, baseline <= 0, or either input is missing",
        "units": "1",
    })
    print(f"LOG RATIO VALID CELLS : {int(valid.sum())}")
    print(f"LOG RATIO MASKED CELLS: {int(valid.size - valid.sum())}")

    ds_out = ds_future.copy(deep=True)
    ds_out[future_var] = da_delta
    ds_out.attrs = ds_future.attrs.copy()
    ds_out.attrs.update({
        "delta_mode": delta_mode,
        "delta_baseline_file": baseline_file,
        "delta_future_file": future_file,
    })
    ds_out.to_netcdf(tmp_delta, format="NETCDF4")
PY
fi
mv -f "${TMP_DELTA}" "${DELTA_FILE}"
echo "[DONE ] ${DELTA_FILE}"

if [[ "$REGRID_DELTA" == "yes" ]]; then
  REGRID_FILE="${REGRID_OUT_DIR}/${OUT_PREFIX}_delta_${FUTURE_TAG}_minus_${BASELINE_TAG}_${REGRID_SUFFIX}.nc"
  TMP_REGRID="${TMP_DIR}/${OUT_PREFIX}_delta_${FUTURE_TAG}_minus_${BASELINE_TAG}_${REGRID_SUFFIX}.tmp.nc"

  rm -f "${REGRID_FILE}" "${TMP_REGRID}"

  echo "[STEP3] Regridding delta"
  cdo -L -O ${METHOD},"${GRIDFILE}" "${DELTA_FILE}" "${TMP_REGRID}"
  mv -f "${TMP_REGRID}" "${REGRID_FILE}"
  echo "[DONE ] ${REGRID_FILE}"
fi

echo
echo "All climatology delta processing completed for VAR=${VAR}"
