#!/usr/bin/env bash
# ==============================================================================
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=cesm_regrid
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=5
#SBATCH --mem=128G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/regrid_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/regrid_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# CESM vertical regridding to GLORYS depth levels
#
# Expected input:
#   /home/SB5/rcp85/<VAR>/merged/*.nc
#
# Creates:
#   /home/SB5/rcp85/<VAR>/tmp_vgrid/
#   /home/SB5/rcp85/<VAR>/on_glorys/
#
# Shared helper files:
#   /home/SB5/tmp/cesm_zaxis_m.txt
#   /home/SB5/tmp/glorys_zaxis.txt
#
# Notes:
# - Only reads from merged/
# - Never touches parts/
# - Parallelization is over .nc files, max 5 at a time
# - Temp *_m.nc files are deleted after successful intlevel
# ==============================================================================

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------
MAX_JOBS=5

SB5_ROOT="/home/SB5"
RCP85_ROOT="${SB5_ROOT}/rcp85"
GLORYS_ROOT="${SB5_ROOT}/glorys12v1_monthly_0p05"
SHARED_TMP="${SB5_ROOT}/tmp"

GLORYS_THETAO_PARTS="${GLORYS_ROOT}/thetao/parts"
GLORYS_ZAXIS="${SHARED_TMP}/glorys_zaxis.txt"
CESM_ZAXIS_M="${SHARED_TMP}/cesm_zaxis_m.txt"

VAR="${VAR:-}"

# ------------------------------------------------------------------------------
# Checks
# ------------------------------------------------------------------------------
if [[ -z "${VAR}" ]]; then
  echo "ERROR: VAR is not set."
  echo "Submit like: VAR=O2 sbatch cesm_vertical_regrid.slurm.sh"
  exit 1
fi

IN_DIR="${RCP85_ROOT}/${VAR}/merged"
TMP_DIR="${RCP85_ROOT}/${VAR}/tmp_vgrid"
OUT_DIR="${RCP85_ROOT}/${VAR}/on_glorys"

if [[ ! -d "${IN_DIR}" ]]; then
  echo "ERROR: Input directory does not exist: ${IN_DIR}"
  exit 1
fi

mkdir -p "${SHARED_TMP}" "${TMP_DIR}" "${OUT_DIR}"

echo "============================================================"
echo "Starting CESM vertical regrid"
echo "VAR       : ${VAR}"
echo "INPUT DIR : ${IN_DIR}"
echo "TMP DIR   : ${TMP_DIR}"
echo "OUT DIR   : ${OUT_DIR}"
echo "MAX JOBS  : ${MAX_JOBS}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Build shared GLORYS z-axis template once, if missing
# ------------------------------------------------------------------------------
if [[ -f "${GLORYS_ZAXIS}" ]]; then
  echo "Using existing GLORYS z-axis template:"
  echo "  ${GLORYS_ZAXIS}"
else
  echo "GLORYS z-axis template not found. Creating it now..."

  GLORYS_FIRST_FILE="$(find "${GLORYS_THETAO_PARTS}" -maxdepth 1 -type f -name '*.nc' | sort | head -n 1)"

  if [[ -z "${GLORYS_FIRST_FILE}" ]]; then
    echo "ERROR: Could not find a GLORYS thetao .nc file in:"
    echo "  ${GLORYS_THETAO_PARTS}"
    exit 1
  fi

  echo "Using GLORYS template source file:"
  echo "  ${GLORYS_FIRST_FILE}"

  cdo zaxisdes "${GLORYS_FIRST_FILE}" > "${GLORYS_ZAXIS}"

  echo "Created:"
  echo "  ${GLORYS_ZAXIS}"
fi

# ------------------------------------------------------------------------------
# Build shared CESM z-axis descriptor in meters once, if missing
# ------------------------------------------------------------------------------
if [[ -f "${CESM_ZAXIS_M}" ]]; then
  echo "Using existing CESM z-axis descriptor in meters:"
  echo "  ${CESM_ZAXIS_M}"
else
  echo "CESM z-axis descriptor not found. Creating it now..."

  CESM_FIRST_FILE="$(find "${IN_DIR}" -maxdepth 1 -type f -name '*.nc' | sort | head -n 1)"

  if [[ -z "${CESM_FIRST_FILE}" ]]; then
    echo "ERROR: Could not find any CESM .nc file in:"
    echo "  ${IN_DIR}"
    exit 1
  fi

  echo "Using CESM source file:"
  echo "  ${CESM_FIRST_FILE}"

  LEVELS_RAW="$(cdo showlevel "${CESM_FIRST_FILE}" | tr ' ' '\n' | awk 'NF')"
  NLEVELS="$(printf "%s\n" "${LEVELS_RAW}" | wc -l | awk '{print $1}')"
  LEVELS_M="$(printf "%s\n" "${LEVELS_RAW}" | awk 'NF{printf "%s ", $1/100}')"

  cat > "${CESM_ZAXIS_M}" <<EOF
zaxistype = generic
size      = ${NLEVELS}
name      = z_t
longname  = ocean depth
units     = m
levels    = ${LEVELS_M}
EOF

  echo "Created:"
  echo "  ${CESM_ZAXIS_M}"
fi

# ------------------------------------------------------------------------------
# Per-file processing function
# ------------------------------------------------------------------------------
process_one_file() {
  local infile="$1"
  local base
  local tmpfile
  local outfile

  base="$(basename "${infile}" .nc)"
  tmpfile="${TMP_DIR}/${base}_m.nc"
  outfile="${OUT_DIR}/${base}_on_glorys.nc"

  echo
  echo "[START] ${base}"

  if [[ -f "${outfile}" ]]; then
    echo "[SKIP ] Output already exists: ${outfile}"
    return 0
  fi

  if [[ -f "${tmpfile}" ]]; then
    echo "[WARN ] Removing stale temp file: ${tmpfile}"
    rm -f "${tmpfile}"
  fi

  echo "[STEP1] Fixing CESM z-axis from cm to m"
  cdo setattribute,z_t@units="m" -setzaxis,"${CESM_ZAXIS_M}" "${infile}" "${tmpfile}"

  echo "[STEP2] Interpolating vertically onto GLORYS levels"
  cdo intlevel,zdescription="${GLORYS_ZAXIS}" "${tmpfile}" "${outfile}"

  echo "[STEP3] Cleaning temp file"
  rm -f "${tmpfile}"

  echo "[DONE ] ${outfile}"
}

export SB5_ROOT RCP85_ROOT GLORYS_ROOT SHARED_TMP
export GLORYS_THETAO_PARTS GLORYS_ZAXIS CESM_ZAXIS_M
export VAR IN_DIR TMP_DIR OUT_DIR MAX_JOBS
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
echo "All processing completed for VAR=${VAR}"