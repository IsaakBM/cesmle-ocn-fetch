#!/usr/bin/env bash
# ==============================================================================
#  Generic climatology window builder from monthly files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read monthly files already prepared for one variable
#    - Select files that fall within a requested climatology window
#    - Compute one single climatology file per variable by averaging all monthly
#      values across that full window
#    - Follow the same full-window mean logic used in the existing GLORYS
#      climatology workflow
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=clim_window
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH -t 7-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/clim_window_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/clim_window_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Required env vars (passed at sbatch time)
#   DATASET_LABEL : short dataset label for logs and output names
#   VAR           : variable to process
#   IN_DIR        : directory with monthly input files
#   OUT_DIR       : directory where climatology outputs will be written
#
# Optional env vars
#   TMP_DIR         : temp directory (default: <OUT_DIR>/tmp_clim)
#   FILE_GLOB       : input file glob (default: *.nc)
#   DATE_PATTERN    : grep -E pattern that extracts YYYYMM from filename
#                     default: [0-9]{6}
#   WINDOW_START    : start YYYYMM (default: 200601)
#   WINDOW_END      : end YYYYMM (default: 201412)
#   EXPECTED_N      : expected number of monthly files (default: 108)
#   OUT_PREFIX      : output filename prefix (default: <DATASET_LABEL>_<VAR>)
# ==============================================================================
DATASET_LABEL="${DATASET_LABEL:-dataset}"
VAR="${VAR:-}"
IN_DIR="${IN_DIR:-}"
OUT_DIR="${OUT_DIR:-}"

TMP_DIR="${TMP_DIR:-}"
FILE_GLOB="${FILE_GLOB:-*.nc}"
DATE_PATTERN="${DATE_PATTERN:-[0-9]{6}}"
WINDOW_START="${WINDOW_START:-200601}"
WINDOW_END="${WINDOW_END:-201412}"
EXPECTED_N="${EXPECTED_N:-108}"
OUT_PREFIX="${OUT_PREFIX:-}"

if [[ -z "$VAR" || -z "$IN_DIR" || -z "$OUT_DIR" ]]; then
  echo "ERROR: Missing required environment variables."
  echo "Required: VAR, IN_DIR, OUT_DIR"
  echo "Optional: DATASET_LABEL, TMP_DIR, FILE_GLOB, DATE_PATTERN, WINDOW_START, WINDOW_END, EXPECTED_N, OUT_PREFIX"
  exit 1
fi

if [[ ! -d "$IN_DIR" ]]; then
  echo "ERROR: Input directory does not exist: ${IN_DIR}"
  exit 1
fi

if [[ ! "$WINDOW_START" =~ ^[0-9]{6}$ || ! "$WINDOW_END" =~ ^[0-9]{6}$ ]]; then
  echo "ERROR: WINDOW_START and WINDOW_END must be in YYYYMM format."
  exit 1
fi

if [[ -z "$TMP_DIR" ]]; then
  TMP_DIR="${OUT_DIR}/tmp_clim"
fi

if [[ -z "$OUT_PREFIX" ]]; then
  OUT_PREFIX="${DATASET_LABEL}_${VAR}"
fi

mkdir -p "${OUT_DIR}" "${TMP_DIR}"

echo "============================================================"
echo "Starting climatology window processing"
echo "DATASET     : ${DATASET_LABEL}"
echo "VAR         : ${VAR}"
echo "INPUT DIR   : ${IN_DIR}"
echo "OUT DIR     : ${OUT_DIR}"
echo "TMP DIR     : ${TMP_DIR}"
echo "FILE GLOB   : ${FILE_GLOB}"
echo "DATE PATTERN: ${DATE_PATTERN}"
echo "WINDOW      : ${WINDOW_START} to ${WINDOW_END}"
echo "OUT PREFIX  : ${OUT_PREFIX}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Gather files inside the target window
# ------------------------------------------------------------------------------
FILES=( "${IN_DIR}"/${FILE_GLOB} )

VALID_FILES=()
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue

  bn="$(basename "$f")"
  yyyymm="$(printf "%s\n" "$bn" | grep -oE "${DATE_PATTERN}" | head -n 1 || true)"

  if [[ -z "${yyyymm}" ]]; then
    continue
  fi

  if [[ "${yyyymm}" < "${WINDOW_START}" || "${yyyymm}" > "${WINDOW_END}" ]]; then
    continue
  fi

  yyyy="${yyyymm:0:4}"
  mm="${yyyymm:4:2}"
  if [[ "${yyyy}" =~ ^[0-9]{4}$ ]] && [[ "${mm}" =~ ^(01|02|03|04|05|06|07|08|09|10|11|12)$ ]]; then
    VALID_FILES+=( "$f" )
  fi
done

if [[ ${#VALID_FILES[@]} -eq 0 ]]; then
  echo "ERROR: No valid monthly files found for ${VAR} in ${IN_DIR}"
  exit 1
fi

IFS=$'\n' VALID_FILES=( $(printf "%s\n" "${VALID_FILES[@]}" | sort) )
unset IFS

echo "Found ${#VALID_FILES[@]} monthly files in requested window."

if [[ -n "${EXPECTED_N}" && "${#VALID_FILES[@]}" -ne "${EXPECTED_N}" ]]; then
  echo "WARN: Expected ${EXPECTED_N} monthly files, found ${#VALID_FILES[@]}"
  echo "      Proceeding anyway."
fi

# ------------------------------------------------------------------------------
# Output names
# ------------------------------------------------------------------------------
OUTFILE="${OUT_DIR}/${OUT_PREFIX}_clim_${WINDOW_START:0:4}-${WINDOW_END:0:4}.nc"
TMP_OUT="${TMP_DIR}/${OUT_PREFIX}_clim_${WINDOW_START:0:4}-${WINDOW_END:0:4}.tmp.nc"

# ------------------------------------------------------------------------------
# Processing
# ------------------------------------------------------------------------------
echo "[STEP1] Removing old output if present"
rm -f "${OUTFILE}" "${TMP_OUT}"

echo "[STEP2] Computing climatological mean directly from monthly files"
cdo -L -O timmean -mergetime "${VALID_FILES[@]}" "${TMP_OUT}"

echo "[STEP3] Writing final output"
mv -f "${TMP_OUT}" "${OUTFILE}"

echo "[DONE ] ${OUTFILE}"
echo
echo "All climatology window processing completed for VAR=${VAR}"
