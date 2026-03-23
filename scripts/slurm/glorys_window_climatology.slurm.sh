#!/usr/bin/env bash
# ==============================================================================
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=glorys_clim
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH -t 3-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys_clim_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys_clim_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# GLORYS baseline climatology (Bio-ORACLE-style mean over monthly files)
#
# Purpose:
#   - Read GLORYS monthly files already produced at 0.05 degree resolution
#   - Use all monthly files from 2006-01 to 2014-12
#   - Compute one single climatology file per variable by averaging all monthly
#     values across that full baseline window
#
# Expected input:
#   /home/SB5/glorys12v1_monthly_0p05/<VAR>/parts/*.nc
#
# Creates:
#   /home/SB5/glorys12v1_monthly_0p05/<VAR>/clim_windows/
#   /home/SB5/glorys12v1_monthly_0p05/<VAR>/tmp_clim/
#
# Notes:
# - Only reads from parts/
# - Produces one file:
#     glorys12v1_<VAR>_clim_2006-2014.nc
# - Temp merged file is deleted after successful completion
# - Follows the requested Bio-ORACLE-style approach:
#     one mean over all monthly values in the baseline window
# ==============================================================================

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------
SB5_ROOT="/home/SB5"
GLORYS_ROOT="${SB5_ROOT}/glorys12v1_monthly_0p05"

VAR="${VAR:-}"

# ------------------------------------------------------------------------------
# Checks
# ------------------------------------------------------------------------------
if [[ -z "${VAR}" ]]; then
  echo "ERROR: VAR is not set."
  echo "Submit like: VAR=thetao sbatch glorys_window_climatology.slurm.sh"
  exit 1
fi

IN_DIR="${GLORYS_ROOT}/${VAR}/parts"
OUT_DIR="${GLORYS_ROOT}/${VAR}/clim_windows"
TMP_DIR="${GLORYS_ROOT}/${VAR}/tmp_clim"

if [[ ! -d "${IN_DIR}" ]]; then
  echo "ERROR: Input directory does not exist: ${IN_DIR}"
  exit 1
fi

mkdir -p "${OUT_DIR}" "${TMP_DIR}"

echo "============================================================"
echo "Starting GLORYS baseline climatology"
echo "VAR       : ${VAR}"
echo "INPUT DIR : ${IN_DIR}"
echo "OUT DIR   : ${OUT_DIR}"
echo "TMP DIR   : ${TMP_DIR}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Gather baseline files
# ------------------------------------------------------------------------------
FILES=( "${IN_DIR}"/glorys12v1_"${VAR}"_200[6-9][0-1][0-9].monmean.0p05.nc
        "${IN_DIR}"/glorys12v1_"${VAR}"_201[0-4][0-1][0-9].monmean.0p05.nc )

# Keep only months 01-12 and years 2006-2014
VALID_FILES=()
for f in "${FILES[@]}"; do
  bn="$(basename "$f")"
  yyyymm="$(echo "$bn" | sed -n 's/.*_\([0-9]\{6\}\)\.monmean.0p05.nc/\1/p')"
  if [[ -n "${yyyymm}" ]]; then
    yyyy="${yyyymm:0:4}"
    mm="${yyyymm:4:2}"
    if [[ "${yyyy}" =~ ^200[6-9]$|^201[0-4]$ ]] && [[ "${mm}" =~ ^(01|02|03|04|05|06|07|08|09|10|11|12)$ ]]; then
      VALID_FILES+=( "$f" )
    fi
  fi
done

if [[ ${#VALID_FILES[@]} -eq 0 ]]; then
  echo "ERROR: No valid monthly files found for ${VAR} in ${IN_DIR}"
  exit 1
fi

# Sort for safety
IFS=$'\n' VALID_FILES=( $(printf "%s\n" "${VALID_FILES[@]}" | sort) )
unset IFS

echo "Found ${#VALID_FILES[@]} monthly files for 2006-2014."

EXPECTED_N=108
if [[ ${#VALID_FILES[@]} -ne ${EXPECTED_N} ]]; then
  echo "WARN: Expected ${EXPECTED_N} monthly files, found ${#VALID_FILES[@]}"
  echo "      Proceeding anyway."
fi

# ------------------------------------------------------------------------------
# Output names
# ------------------------------------------------------------------------------
OUTFILE="${OUT_DIR}/glorys12v1_${VAR}_clim_2006-2014.nc"
TMP_MERGED="${TMP_DIR}/glorys12v1_${VAR}_2006-2014_merged.tmp.nc"
TMP_OUT="${TMP_DIR}/glorys12v1_${VAR}_clim_2006-2014.tmp.nc"

# ------------------------------------------------------------------------------
# Processing
# ------------------------------------------------------------------------------
echo "[STEP1] Removing old output if present"
rm -f "${OUTFILE}" "${TMP_MERGED}" "${TMP_OUT}"

echo "[STEP2] Merging monthly files"
cdo -L -O mergetime "${VALID_FILES[@]}" "${TMP_MERGED}"

echo "[STEP3] Computing climatological mean over all monthly values"
cdo -L -O timmean "${TMP_MERGED}" "${TMP_OUT}"

echo "[STEP4] Writing final output"
mv -f "${TMP_OUT}" "${OUTFILE}"

echo "[STEP5] Cleaning temp files"
rm -f "${TMP_MERGED}"

echo "[DONE ] ${OUTFILE}"
echo
echo "All climatology processing completed for VAR=${VAR}"