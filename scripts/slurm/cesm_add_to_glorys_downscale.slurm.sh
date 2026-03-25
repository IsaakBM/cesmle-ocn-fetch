#!/usr/bin/env bash
# ==============================================================================
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=cesm_add
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=256G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/add_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/add_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
export OMP_NUM_THREADS=1
shopt -s nullglob

# ==============================================================================
# Add CESM member anomalies to GLORYS baseline climatology
#
# Purpose:
#   - Read GLORYS baseline climatology for the matching target variable
#   - Read CESM member-level anomalies already remapped to 0.05 degree
#   - Fill the first 4 shallow GLORYS levels in the anomaly field using the
#     first valid CESM-derived anomaly layer, at the GLORYS level near 5.078 m
#   - Add the filled anomaly field to the GLORYS baseline
#   - Produce one downscaled product per ensemble member and per future window
#
# Expected input:
#   GLORYS baseline:
#     /home/SB5/glorys12v1_monthly_0p05/<GLORYS_VAR>/clim_windows/
#       glorys12v1_<GLORYS_VAR>_clim_2006-2014.nc
#
#   CESM member anomalies at 0.05 degree:
#     /home/SB5/rcp85/<CESM_VAR>/delta_windows/member_deltas_0p05/*.nc
#
# Creates:
#   /home/SB5/downscaled_rcp85/<GLORYS_VAR>/<WINDOW>/
#   /home/SB5/downscaled_rcp85/<GLORYS_VAR>/tmp_add/
#
# Notes:
# - Variable matching is:
#     TEMP -> thetao
#     SALT -> so
#     UVEL -> uo
# - No ensemble mean is computed here
# - Parallelization is over member anomaly files
# - Top 4 GLORYS levels are filled from the first valid anomaly layer before
#   adding anomalies to the GLORYS baseline
# ==============================================================================

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------
MAX_JOBS=2

SB5_ROOT="/home/SB5"
RCP85_ROOT="${SB5_ROOT}/rcp85"
GLORYS_ROOT="${SB5_ROOT}/glorys12v1_monthly_0p05"
OUTROOT="${SB5_ROOT}/downscaled_rcp85"

CESM_VAR="${VAR:-}"

# ------------------------------------------------------------------------------
# Match CESM variable to GLORYS target variable
# ------------------------------------------------------------------------------
case "${CESM_VAR}" in
  TEMP)
    GLORYS_VAR="thetao"
    ;;
  SALT)
    GLORYS_VAR="so"
    ;;
  UVEL)
    GLORYS_VAR="uo"
    ;;
  *)
    echo "ERROR: Unsupported VAR='${CESM_VAR}'"
    echo "Supported values: TEMP, SALT, UVEL"
    exit 1
    ;;
esac

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
BASELINE_FILE="${GLORYS_ROOT}/${GLORYS_VAR}/clim_windows/glorys12v1_${GLORYS_VAR}_clim_2006-2014.nc"
ANOM_DIR="${RCP85_ROOT}/${CESM_VAR}/delta_windows/member_deltas_0p05"

OUT_VAR_DIR="${OUTROOT}/${GLORYS_VAR}"
OUT_2050_DIR="${OUT_VAR_DIR}/2050-2060"
OUT_2090_DIR="${OUT_VAR_DIR}/2090-2100"
TMP_DIR="${OUT_VAR_DIR}/tmp_add"

mkdir -p "${OUT_2050_DIR}" "${OUT_2090_DIR}" "${TMP_DIR}"

# ------------------------------------------------------------------------------
# Checks
# ------------------------------------------------------------------------------
if [[ -z "${CESM_VAR}" ]]; then
  echo "ERROR: VAR is not set."
  echo "Submit like: VAR=TEMP sbatch cesm_add_to_glorys_downscale.slurm.sh"
  exit 1
fi

if [[ ! -f "${BASELINE_FILE}" ]]; then
  echo "ERROR: GLORYS baseline file not found:"
  echo "  ${BASELINE_FILE}"
  exit 1
fi

if [[ ! -d "${ANOM_DIR}" ]]; then
  echo "ERROR: Anomaly directory not found:"
  echo "  ${ANOM_DIR}"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is not available in PATH"
  exit 1
fi

echo "============================================================"
echo "Starting GLORYS + CESM member downscaling"
echo "CESM VAR      : ${CESM_VAR}"
echo "GLORYS VAR    : ${GLORYS_VAR}"
echo "BASELINE FILE : ${BASELINE_FILE}"
echo "ANOM DIR      : ${ANOM_DIR}"
echo "OUT ROOT      : ${OUT_VAR_DIR}"
echo "TMP DIR       : ${TMP_DIR}"
echo "MAX JOBS      : ${MAX_JOBS}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Future window tags
# ------------------------------------------------------------------------------
FUT1_TAG="2050-2060"
FUT2_TAG="2090-2100"
BASE_TAG="2006-2014"

# ------------------------------------------------------------------------------
# Per-file processing function
# ------------------------------------------------------------------------------
process_one_anomaly_file() {
  local anom_file="$1"
  local future_tag="$2"

  local anom_name member_tag out_file
  local out_dir

  anom_name="$(basename "${anom_file}")"

  case "${future_tag}" in
    "${FUT1_TAG}")
      out_dir="${OUT_2050_DIR}"
      ;;
    "${FUT2_TAG}")
      out_dir="${OUT_2090_DIR}"
      ;;
    *)
      echo "[ERROR] Unknown future tag: ${future_tag}"
      return 1
      ;;
  esac

  member_tag="${anom_name%_delta_${future_tag}_minus_${BASE_TAG}_0p05.nc}"
  out_file="${out_dir}/${member_tag}_downscaled_${GLORYS_VAR}_${future_tag}.nc"

  echo
  echo "[START] ${anom_name}"

  rm -f "${out_file}"

  echo "[STEP1] Filling top 4 shallow anomaly layers from first valid layer"
  echo "[STEP2] Adding filled anomaly to GLORYS baseline"

  python3 - <<PY
import xarray as xr

baseline_file = "${BASELINE_FILE}"
anom_file = "${anom_file}"
out_file = "${out_file}"

ds_base = xr.open_dataset(baseline_file)
ds_anom = xr.open_dataset(anom_file)

# Pick the real baseline variable, ignore bounds-like variables
base_candidates = [
    v for v in ds_base.data_vars
    if "bnds" not in v.lower() and "bounds" not in v.lower()
]
if not base_candidates:
    raise ValueError(f"No valid baseline data variable found in: {list(ds_base.data_vars)}")
var_base = base_candidates[0]

# Pick the real anomaly variable, ignore bounds-like variables
anom_candidates = [
    v for v in ds_anom.data_vars
    if "bnds" not in v.lower() and "bounds" not in v.lower()
]
if not anom_candidates:
    raise ValueError(f"No valid anomaly data variable found in: {list(ds_anom.data_vars)}")

# Prefer the variable that has a vertical dimension
zdim_names = ("depth", "depth_below_sea", "lev", "z_t")
var_anom = None
for v in anom_candidates:
    dims_lower = tuple(d.lower() for d in ds_anom[v].dims)
    if any(z in dims_lower for z in zdim_names):
        var_anom = v
        break

if var_anom is None:
    raise ValueError(
        f"Could not find anomaly variable with vertical dimension. "
        f"Candidates: {[(v, ds_anom[v].dims) for v in anom_candidates]}"
    )

da_base = ds_base[var_base]
da_anom = ds_anom[var_anom]

zdim_candidates = [d for d in da_anom.dims if d.lower() in zdim_names]
if not zdim_candidates:
    raise ValueError(f"Could not identify vertical dimension in anomaly dims: {da_anom.dims}")
zdim = zdim_candidates[0]

# Copy anomaly from the first valid CESM-derived layer (index 4, 5th level)
# upward into the first 4 GLORYS levels
da_anom_filled = da_anom.copy()
top_template = da_anom.isel({zdim: 4})
for i in range(4):
    da_anom_filled[{zdim: i}] = top_template

da_out = da_base + da_anom_filled
da_out.name = var_base

ds_out = ds_base.copy()
ds_out[var_base] = da_out

encoding = {var_base: {"zlib": True, "complevel": 1}}
ds_out.to_netcdf(out_file, format="NETCDF4", encoding=encoding)

ds_base.close()
ds_anom.close()
PY

  echo "[DONE ] ${out_file}"
}

export BASELINE_FILE TMP_DIR OUT_2050_DIR OUT_2090_DIR
export FUT1_TAG FUT2_TAG BASE_TAG GLORYS_VAR ANOM_DIR MAX_JOBS
export -f process_one_anomaly_file

# ------------------------------------------------------------------------------
# Process one future window
# ------------------------------------------------------------------------------
process_window() {
  local future_tag="$1"
  local files=()

  files=( "${ANOM_DIR}"/*"_delta_${future_tag}_minus_${BASE_TAG}_0p05.nc" )

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "ERROR: No anomaly files found for ${future_tag} in:"
    echo "  ${ANOM_DIR}"
    exit 1
  fi

  echo
  echo "------------------------------------------------------------"
  echo "Processing future window: ${future_tag}"
  echo "Found ${#files[@]} member anomaly files."
  echo "------------------------------------------------------------"

  local running=0
  for f in "${files[@]}"; do
    process_one_anomaly_file "${f}" "${future_tag}" &
    ((running+=1))

    if (( running >= MAX_JOBS )); then
      wait -n
      ((running-=1))
    fi
  done

  wait
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
process_window "${FUT1_TAG}"
process_window "${FUT2_TAG}"

echo
echo "All downscaling completed for VAR=${CESM_VAR}"