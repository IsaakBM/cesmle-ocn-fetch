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
REGRID_DELTA="${REGRID_DELTA:-no}"
GRIDFILE="${GRIDFILE:-}"
METHOD="${METHOD:-remapbil}"
REGRID_OUT_DIR="${REGRID_OUT_DIR:-}"
REGRID_SUFFIX="${REGRID_SUFFIX:-}"

if [[ -z "$VAR" || -z "$BASELINE_FILE" || -z "$FUTURE_FILE" || -z "$OUT_DIR" ]]; then
  echo "ERROR: Missing required environment variables."
  echo "Required: VAR, BASELINE_FILE, FUTURE_FILE, OUT_DIR"
  echo "Optional: DATASET_LABEL, TMP_DIR, FUTURE_TAG, BASELINE_TAG, OUT_PREFIX, REGRID_DELTA, GRIDFILE, METHOD, REGRID_OUT_DIR, REGRID_SUFFIX"
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

echo "[STEP2] Computing delta: future minus baseline"
cdo -L -O sub "${FUTURE_FILE}" "${BASELINE_FILE}" "${TMP_DELTA}"
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
