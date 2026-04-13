#!/usr/bin/env bash
# ==============================================================================
#  Generic climatology window builder from time-series files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read one time-series file, or multiple time-series files, for a variable
#    - Select a requested climatology time window with CDO
#    - Compute one single climatology file by averaging all values in that
#      window
#    - Support dataset-agnostic workflows such as CESM members, hindcast files,
#      or any other long-form monthly time series
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=clim_timeseries
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH -t 7-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/clim_timeseries_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/clim_timeseries_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Required env vars (passed at sbatch time)
#   DATASET_LABEL : short dataset label for logs and output names
#   VAR           : variable to process
#   OUT_DIR       : directory where climatology outputs will be written
#
# Required input mode env vars
#   Either:
#     IN_FILE     : single input time-series file
#   Or:
#     IN_DIR      : directory with time-series files
#     FILE_GLOB   : file glob to select input files inside IN_DIR
#
# Optional env vars
#   TMP_DIR         : temp directory (default: <OUT_DIR>/tmp_clim)
#   WINDOW_START    : start date YYYY-MM-DD (default: 2006-01-01)
#   WINDOW_END      : end date YYYY-MM-DD (default: 2014-12-31)
#   OUT_PREFIX      : output filename prefix (default: <DATASET_LABEL>_<VAR>)
#   MERGE_INPUTS    : yes | no (default: auto)
#                     auto merges when more than one file is provided
# ==============================================================================
DATASET_LABEL="${DATASET_LABEL:-dataset}"
VAR="${VAR:-}"
OUT_DIR="${OUT_DIR:-}"

IN_FILE="${IN_FILE:-}"
IN_DIR="${IN_DIR:-}"
FILE_GLOB="${FILE_GLOB:-*.nc}"

TMP_DIR="${TMP_DIR:-}"
WINDOW_START="${WINDOW_START:-2006-01-01}"
WINDOW_END="${WINDOW_END:-2014-12-31}"
OUT_PREFIX="${OUT_PREFIX:-}"
MERGE_INPUTS="${MERGE_INPUTS:-auto}"

if [[ -z "$VAR" || -z "$OUT_DIR" ]]; then
  echo "ERROR: Missing required environment variables."
  echo "Required: VAR, OUT_DIR"
  echo "Provide either IN_FILE or IN_DIR (+ FILE_GLOB)."
  exit 1
fi

if [[ -z "$IN_FILE" && -z "$IN_DIR" ]]; then
  echo "ERROR: Provide either IN_FILE or IN_DIR."
  exit 1
fi

if [[ -n "$IN_FILE" && -n "$IN_DIR" ]]; then
  echo "ERROR: Use either IN_FILE or IN_DIR, not both."
  exit 1
fi

if [[ "$MERGE_INPUTS" != "yes" && "$MERGE_INPUTS" != "no" && "$MERGE_INPUTS" != "auto" ]]; then
  echo "ERROR: MERGE_INPUTS must be one of: yes, no, auto"
  exit 1
fi

if [[ -n "$IN_FILE" && ! -f "$IN_FILE" ]]; then
  echo "ERROR: Input file not found: ${IN_FILE}"
  exit 1
fi

if [[ -n "$IN_DIR" && ! -d "$IN_DIR" ]]; then
  echo "ERROR: Input directory not found: ${IN_DIR}"
  exit 1
fi

if [[ -z "$TMP_DIR" ]]; then
  TMP_DIR="${OUT_DIR}/tmp_clim"
fi

if [[ -z "$OUT_PREFIX" ]]; then
  OUT_PREFIX="${DATASET_LABEL}_${VAR}"
fi

mkdir -p "${OUT_DIR}" "${TMP_DIR}"

INPUTS=()
if [[ -n "$IN_FILE" ]]; then
  INPUTS=( "$IN_FILE" )
else
  INPUTS=( "${IN_DIR}"/${FILE_GLOB} )
fi

REAL_INPUTS=()
for f in "${INPUTS[@]}"; do
  [[ -f "$f" ]] || continue
  REAL_INPUTS+=( "$f" )
done

if [[ ${#REAL_INPUTS[@]} -eq 0 ]]; then
  echo "ERROR: No input files found."
  exit 1
fi

echo "============================================================"
echo "Starting climatology window processing from time-series input"
echo "DATASET      : ${DATASET_LABEL}"
echo "VAR          : ${VAR}"
if [[ -n "$IN_FILE" ]]; then
  echo "INPUT FILE   : ${IN_FILE}"
else
  echo "INPUT DIR    : ${IN_DIR}"
  echo "FILE GLOB    : ${FILE_GLOB}"
fi
echo "OUT DIR      : ${OUT_DIR}"
echo "TMP DIR      : ${TMP_DIR}"
echo "WINDOW       : ${WINDOW_START} to ${WINDOW_END}"
echo "OUT PREFIX   : ${OUT_PREFIX}"
echo "MERGE INPUTS : ${MERGE_INPUTS}"
echo "============================================================"

OUTFILE="${OUT_DIR}/${OUT_PREFIX}_clim_${WINDOW_START:0:4}-${WINDOW_END:0:4}.nc"
TMP_MERGED="${TMP_DIR}/${OUT_PREFIX}_merged_${WINDOW_START:0:4}-${WINDOW_END:0:4}.tmp.nc"
TMP_SEL="${TMP_DIR}/${OUT_PREFIX}_sel_${WINDOW_START:0:4}-${WINDOW_END:0:4}.tmp.nc"
TMP_OUT="${TMP_DIR}/${OUT_PREFIX}_clim_${WINDOW_START:0:4}-${WINDOW_END:0:4}.tmp.nc"

echo "[STEP1] Removing old output if present"
rm -f "${OUTFILE}" "${TMP_MERGED}" "${TMP_SEL}" "${TMP_OUT}"

INPUT_MODE="$MERGE_INPUTS"
if [[ "$INPUT_MODE" == "auto" ]]; then
  if [[ ${#REAL_INPUTS[@]} -gt 1 ]]; then
    INPUT_MODE="yes"
  else
    INPUT_MODE="no"
  fi
fi

if [[ "$INPUT_MODE" == "yes" ]]; then
  echo "[STEP2] Merging input files in time"
  cdo -L -O mergetime "${REAL_INPUTS[@]}" "${TMP_MERGED}"
  SOURCE_FILE="${TMP_MERGED}"
else
  echo "[STEP2] Using single input file without merge"
  SOURCE_FILE="${REAL_INPUTS[0]}"
fi

echo "[STEP3] Selecting climatology window"
cdo -L -O seldate,"${WINDOW_START}","${WINDOW_END}" "${SOURCE_FILE}" "${TMP_SEL}"

echo "[STEP4] Computing climatological mean"
cdo -L -O timmean "${TMP_SEL}" "${TMP_OUT}"

echo "[STEP5] Writing final output"
mv -f "${TMP_OUT}" "${OUTFILE}"

echo "[DONE ] ${OUTFILE}"
echo
echo "All climatology window processing completed for VAR=${VAR}"
