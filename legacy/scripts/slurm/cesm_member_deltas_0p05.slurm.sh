#!/usr/bin/env bash
# ==============================================================================
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=cesm_delta
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=5
#SBATCH --mem=512G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/delta_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/delta_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# CESM member-level deltas and remap to 0.05 degree
#
# Purpose:
#   - Read CESM climatology files already computed per ensemble member
#   - Compute future minus baseline anomaly for each member:
#       * 2050-2060 minus 2006-2014
#       * 2090-2100 minus 2006-2014
#   - Remap each member-level delta to 0.05 degree using remapbil
#
# Expected input:
#   /home/SB5/rcp85/<VAR>/clim_windows/*.nc
#
# Creates:
#   /home/SB5/rcp85/<VAR>/delta_windows/member_deltas/
#   /home/SB5/rcp85/<VAR>/delta_windows/member_deltas_0p05/
#   /home/SB5/rcp85/<VAR>/tmp_delta/
#
# Notes:
# - Parallelization is over ensemble member files
# - No ensemble mean is computed here
# - This step stops after:
#     * member-level delta
#     * member-level delta remapped to 0.05 degree
# ==============================================================================

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------
MAX_JOBS=5

SB5_ROOT="/home/SB5"
RCP85_ROOT="${SB5_ROOT}/rcp85"
GLORYS_ROOT="${SB5_ROOT}/glorys12v1_monthly_0p05"
GRID_0P05="${GLORYS_ROOT}/grid_0p05_global.txt"

VAR="${VAR:-}"

# ------------------------------------------------------------------------------
# Checks
# ------------------------------------------------------------------------------
if [[ -z "${VAR}" ]]; then
  echo "ERROR: VAR is not set."
  echo "Submit like: VAR=TEMP sbatch cesm_member_deltas_0p05.slurm.sh"
  exit 1
fi

IN_DIR="${RCP85_ROOT}/${VAR}/clim_windows"
DELTA_ROOT="${RCP85_ROOT}/${VAR}/delta_windows"
DELTA_DIR="${DELTA_ROOT}/member_deltas"
DELTA_0P05_DIR="${DELTA_ROOT}/member_deltas_0p05"
TMP_DIR="${RCP85_ROOT}/${VAR}/tmp_delta"

if [[ ! -d "${IN_DIR}" ]]; then
  echo "ERROR: Input directory does not exist: ${IN_DIR}"
  exit 1
fi

if [[ ! -f "${GRID_0P05}" ]]; then
  echo "ERROR: Grid file not found: ${GRID_0P05}"
  exit 1
fi

mkdir -p "${DELTA_DIR}" "${DELTA_0P05_DIR}" "${TMP_DIR}"

echo "============================================================"
echo "Starting CESM member-level deltas and remap"
echo "VAR            : ${VAR}"
echo "INPUT DIR      : ${IN_DIR}"
echo "DELTA DIR      : ${DELTA_DIR}"
echo "DELTA 0.05 DIR : ${DELTA_0P05_DIR}"
echo "TMP DIR        : ${TMP_DIR}"
echo "GRID 0.05      : ${GRID_0P05}"
echo "MAX JOBS       : ${MAX_JOBS}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
BASE_TAG="2006-2014"
FUT1_TAG="2050-2060"
FUT2_TAG="2090-2100"

# ------------------------------------------------------------------------------
# Per-file processing function
# ------------------------------------------------------------------------------
process_one_future_file() {
  local future_file="$1"
  local future_tag="$2"

  local future_name base_name base_file
  local delta_name delta_file delta_0p05_name delta_0p05_file
  local tmp_delta tmp_delta_0p05

  future_name="$(basename "${future_file}")"
  base_name="${future_name/_clim_${future_tag}.nc/_clim_${BASE_TAG}.nc}"
  base_file="${IN_DIR}/${base_name}"

  if [[ ! -f "${base_file}" ]]; then
    echo "[ERROR] Missing baseline file for:"
    echo "        ${future_name}"
    return 1
  fi

  delta_name="${future_name/_clim_${future_tag}.nc/_delta_${future_tag}_minus_${BASE_TAG}.nc}"
  delta_file="${DELTA_DIR}/${delta_name}"

  delta_0p05_name="${future_name/_clim_${future_tag}.nc/_delta_${future_tag}_minus_${BASE_TAG}_0p05.nc}"
  delta_0p05_file="${DELTA_0P05_DIR}/${delta_0p05_name}"

  tmp_delta="${TMP_DIR}/${delta_name%.nc}.tmp.nc"
  tmp_delta_0p05="${TMP_DIR}/${delta_0p05_name%.nc}.tmp.nc"

  echo
  echo "[START] ${future_name}"

  rm -f "${tmp_delta}" "${tmp_delta_0p05}" "${delta_file}" "${delta_0p05_file}"

  echo "[STEP1] Computing member delta"
  cdo -L -O sub "${future_file}" "${base_file}" "${tmp_delta}"
  mv -f "${tmp_delta}" "${delta_file}"
  echo "[DONE ] ${delta_file}"

  echo "[STEP2] Remapping member delta to 0.05 degree"
  cdo -L -O remapbil,"${GRID_0P05}" "${delta_file}" "${tmp_delta_0p05}"
  mv -f "${tmp_delta_0p05}" "${delta_0p05_file}"
  echo "[DONE ] ${delta_0p05_file}"
}

export IN_DIR DELTA_DIR DELTA_0P05_DIR TMP_DIR GRID_0P05 BASE_TAG FUT1_TAG FUT2_TAG
export -f process_one_future_file

# ------------------------------------------------------------------------------
# Process one future window
# ------------------------------------------------------------------------------
process_window() {
  local future_tag="$1"
  local files=()

  files=( "${IN_DIR}"/*"_clim_${future_tag}.nc" )

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "ERROR: No climatology files found for window ${future_tag} in ${IN_DIR}"
    exit 1
  fi

  echo
  echo "------------------------------------------------------------"
  echo "Processing future window: ${future_tag}"
  echo "Found ${#files[@]} member files."
  echo "------------------------------------------------------------"

  local running=0
  for f in "${files[@]}"; do
    process_one_future_file "${f}" "${future_tag}" &
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
echo "All member delta processing completed for VAR=${VAR}"