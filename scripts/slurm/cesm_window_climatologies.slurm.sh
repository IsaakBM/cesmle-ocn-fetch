#!/usr/bin/env bash
# ==============================================================================
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=cesm_clims
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=5
#SBATCH --mem=128G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/clims_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/clims_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# CESM climatologies for baseline and future windows
#
# Purpose:
#   - Read CESM ensemble member files already interpolated onto GLORYS depth
#     levels
#   - Compute one climatological mean per member for each target window
#   - Follow the Bio-ORACLE-style approach:
#       * average all monthly values within each window
#       * output one mean file per member per window
#
# Expected input:
#   /home/SB5/rcp85/<VAR>/on_glorys/*.nc
#
# Creates:
#   /home/SB5/rcp85/<VAR>/clim_windows/
#   /home/SB5/rcp85/<VAR>/tmp_clim/
#
# Windows:
#   - baseline: 2006-01 to 2014-12
#   - fut2050s: 2050-01 to 2060-12
#   - fut2090s: 2090-01 to 2100-12
#
# Notes:
# - Parallelization is over ensemble member files
# - One member produces three output files
# - Existing outputs are skipped
# - Temp files are removed after successful completion
# ==============================================================================

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------
MAX_JOBS=5

SB5_ROOT="/home/SB5"
RCP85_ROOT="${SB5_ROOT}/rcp85"

VAR="${VAR:-}"

# ------------------------------------------------------------------------------
# Checks
# ------------------------------------------------------------------------------
if [[ -z "${VAR}" ]]; then
  echo "ERROR: VAR is not set."
  echo "Submit like: VAR=TEMP sbatch cesm_window_climatologies.slurm.sh"
  exit 1
fi

IN_DIR="${RCP85_ROOT}/${VAR}/on_glorys"
OUT_DIR="${RCP85_ROOT}/${VAR}/clim_windows"
TMP_DIR="${RCP85_ROOT}/${VAR}/tmp_clim"

if [[ ! -d "${IN_DIR}" ]]; then
  echo "ERROR: Input directory does not exist: ${IN_DIR}"
  exit 1
fi

mkdir -p "${OUT_DIR}" "${TMP_DIR}"

echo "============================================================"
echo "Starting CESM window climatologies"
echo "VAR       : ${VAR}"
echo "INPUT DIR : ${IN_DIR}"
echo "OUT DIR   : ${OUT_DIR}"
echo "TMP DIR   : ${TMP_DIR}"
echo "MAX JOBS  : ${MAX_JOBS}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Window definitions
# ------------------------------------------------------------------------------
BASE_START="2006-01-01"
BASE_END="2014-12-31"

FUT2050_START="2050-01-01"
FUT2050_END="2060-12-31"

FUT2090_START="2090-01-01"
FUT2090_END="2100-12-31"

# ------------------------------------------------------------------------------
# Per-file processing function
# ------------------------------------------------------------------------------
process_one_file() {
  local infile="$1"
  local base stem out_base out_2050 out_2090
  local tmp_base tmp_2050 tmp_2090

  base="$(basename "${infile}" .nc)"
  stem="${base}"

  out_base="${OUT_DIR}/${stem}_clim_2006-2014.nc"
  out_2050="${OUT_DIR}/${stem}_clim_2050-2060.nc"
  out_2090="${OUT_DIR}/${stem}_clim_2090-2100.nc"

  tmp_base="${TMP_DIR}/${stem}_clim_2006-2014.tmp.nc"
  tmp_2050="${TMP_DIR}/${stem}_clim_2050-2060.tmp.nc"
  tmp_2090="${TMP_DIR}/${stem}_clim_2090-2100.tmp.nc"

  echo
  echo "[START] ${stem}"

  if [[ -f "${out_base}" && -f "${out_2050}" && -f "${out_2090}" ]]; then
    echo "[SKIP ] All outputs already exist for: ${stem}"
    return 0
  fi

  rm -f "${tmp_base}" "${tmp_2050}" "${tmp_2090}"

  if [[ ! -f "${out_base}" ]]; then
    echo "[BASE ] 2006-2014"
    cdo -L -O timmean \
      -seldate,"${BASE_START}","${BASE_END}" \
      "${infile}" "${tmp_base}"
    mv -f "${tmp_base}" "${out_base}"
    echo "[DONE ] ${out_base}"
  else
    echo "[SKIP ] Exists: ${out_base}"
  fi

  if [[ ! -f "${out_2050}" ]]; then
    echo "[2050 ] 2050-2060"
    cdo -L -O timmean \
      -seldate,"${FUT2050_START}","${FUT2050_END}" \
      "${infile}" "${tmp_2050}"
    mv -f "${tmp_2050}" "${out_2050}"
    echo "[DONE ] ${out_2050}"
  else
    echo "[SKIP ] Exists: ${out_2050}"
  fi

  if [[ ! -f "${out_2090}" ]]; then
    echo "[2090 ] 2090-2100"
    cdo -L -O timmean \
      -seldate,"${FUT2090_START}","${FUT2090_END}" \
      "${infile}" "${tmp_2090}"
    mv -f "${tmp_2090}" "${out_2090}"
    echo "[DONE ] ${out_2090}"
  else
    echo "[SKIP ] Exists: ${out_2090}"
  fi
}

export SB5_ROOT RCP85_ROOT
export VAR IN_DIR OUT_DIR TMP_DIR
export BASE_START BASE_END FUT2050_START FUT2050_END FUT2090_START FUT2090_END
export -f process_one_file

# ------------------------------------------------------------------------------
# Gather input files
# ------------------------------------------------------------------------------
FILES=( "${IN_DIR}"/*.nc )

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "ERROR: No .nc files found in ${IN_DIR}"
  exit 1
fi

echo "Found ${#FILES[@]} input files."

# ------------------------------------------------------------------------------
# Parallel execution, max MAX_JOBS at a time
# ------------------------------------------------------------------------------
running=0
for f in "${FILES[@]}"; do
  process_one_file "${f}" &
  ((running+=1))

  if (( running >= MAX_JOBS )); then
    wait -n
    ((running-=1))
  fi
done

wait

echo
echo "All climatology processing completed for VAR=${VAR}"