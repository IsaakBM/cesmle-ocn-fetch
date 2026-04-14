#!/usr/bin/env bash
# ==============================================================================
#  Generic vertical interpolation to reference levels
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read one or more input files with a vertical coordinate
#    - Optionally convert the source vertical coordinate units
#    - Build or reuse a source z-axis descriptor
#    - Build or reuse a target z-axis descriptor from a reference file
#    - Interpolate vertically onto the target levels
#    - Write outputs to a target directory such as on_glorys/
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=vinterp_ref
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=5
#SBATCH --mem=128G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/vinterp_ref_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/vinterp_ref_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Required env vars (passed at sbatch time)
#   DATASET_LABEL      : short dataset label for logs/messages
#   IN_DIR             : directory containing input files
#   OUT_DIR            : directory where vertically interpolated files go
#   TARGET_REF_FILE    : reference NetCDF file used to define target z levels
#
# Optional env vars
#   FILE_GLOB          : input file glob (default: *.nc)
#   SHARED_TMP_DIR     : directory for shared z-axis descriptors
#                        (default: /home/SB5/tmp)
#   TMP_DIR            : temp directory for working files
#                        (default: <OUT_DIR>/tmp_vinterp)
#   TARGET_ZAXIS_FILE  : explicit target z-axis descriptor file
#                        (default: <SHARED_TMP_DIR>/<DATASET_LABEL>_target_zaxis.txt)
#   SOURCE_ZAXIS_FILE  : explicit source z-axis descriptor file
#                        (default: <SHARED_TMP_DIR>/<DATASET_LABEL>_source_zaxis.txt)
#   SOURCE_ZDIM_NAME   : source vertical dimension name (default: z_t)
#   SOURCE_UNITS_IN    : source vertical units: cm | m | none (default: none)
#   SOURCE_UNITS_OUT   : target source units after conversion (default: m)
#   SOURCE_SCALE       : multiplicative factor to convert source levels
#                        (default: auto from SOURCE_UNITS_IN/OUT)
#   OUT_SUFFIX         : output suffix before .nc (default: on_reference)
#   MAX_JOBS           : max parallel files (default: 5)
#   OVERWRITE_OUTPUTS  : yes | no (default: yes)
# ==============================================================================
DATASET_LABEL="${DATASET_LABEL:-dataset}"
IN_DIR="${IN_DIR:-}"
OUT_DIR="${OUT_DIR:-}"
TARGET_REF_FILE="${TARGET_REF_FILE:-}"

FILE_GLOB="${FILE_GLOB:-*.nc}"
SHARED_TMP_DIR="${SHARED_TMP_DIR:-/home/SB5/tmp}"
TMP_DIR="${TMP_DIR:-}"
TARGET_ZAXIS_FILE="${TARGET_ZAXIS_FILE:-}"
SOURCE_ZAXIS_FILE="${SOURCE_ZAXIS_FILE:-}"
SOURCE_ZDIM_NAME="${SOURCE_ZDIM_NAME:-z_t}"
SOURCE_UNITS_IN="${SOURCE_UNITS_IN:-none}"
SOURCE_UNITS_OUT="${SOURCE_UNITS_OUT:-m}"
SOURCE_SCALE="${SOURCE_SCALE:-}"
OUT_SUFFIX="${OUT_SUFFIX:-on_reference}"
MAX_JOBS="${MAX_JOBS:-5}"
OVERWRITE_OUTPUTS="${OVERWRITE_OUTPUTS:-yes}"

if [[ -z "$IN_DIR" || -z "$OUT_DIR" || -z "$TARGET_REF_FILE" ]]; then
  echo "ERROR: Missing required environment variables."
  echo "Required: IN_DIR, OUT_DIR, TARGET_REF_FILE"
  echo "Optional: DATASET_LABEL, FILE_GLOB, SHARED_TMP_DIR, TMP_DIR, TARGET_ZAXIS_FILE, SOURCE_ZAXIS_FILE, SOURCE_ZDIM_NAME, SOURCE_UNITS_IN, SOURCE_UNITS_OUT, SOURCE_SCALE, OUT_SUFFIX, MAX_JOBS"
  exit 1
fi

if [[ ! -d "$IN_DIR" ]]; then
  echo "ERROR: Input directory does not exist: ${IN_DIR}"
  exit 1
fi

if [[ ! -f "$TARGET_REF_FILE" ]]; then
  echo "ERROR: Target reference file not found: ${TARGET_REF_FILE}"
  exit 1
fi

if ! [[ "$MAX_JOBS" =~ ^[0-9]+$ ]] || [[ "$MAX_JOBS" -lt 1 ]]; then
  echo "ERROR: MAX_JOBS must be a positive integer"
  exit 1
fi

if [[ -z "$TMP_DIR" ]]; then
  TMP_DIR="${OUT_DIR}/tmp_vinterp"
fi

if [[ -z "$TARGET_ZAXIS_FILE" ]]; then
  TARGET_ZAXIS_FILE="${SHARED_TMP_DIR}/${DATASET_LABEL}_target_zaxis.txt"
fi

if [[ -z "$SOURCE_ZAXIS_FILE" ]]; then
  SOURCE_ZAXIS_FILE="${SHARED_TMP_DIR}/${DATASET_LABEL}_source_zaxis.txt"
fi

mkdir -p "${SHARED_TMP_DIR}" "${TMP_DIR}" "${OUT_DIR}"

if [[ -z "$SOURCE_SCALE" ]]; then
  case "${SOURCE_UNITS_IN}:${SOURCE_UNITS_OUT}" in
    cm:m)
      SOURCE_SCALE="0.01"
      ;;
    m:m|none:m|none:none|m:none)
      SOURCE_SCALE="1"
      ;;
    *)
      echo "ERROR: Could not infer SOURCE_SCALE for SOURCE_UNITS_IN=${SOURCE_UNITS_IN} and SOURCE_UNITS_OUT=${SOURCE_UNITS_OUT}"
      echo "       Set SOURCE_SCALE explicitly."
      exit 1
      ;;
  esac
fi

echo "============================================================"
echo "Starting generic vertical interpolation"
echo "DATASET LABEL    : ${DATASET_LABEL}"
echo "INPUT DIR        : ${IN_DIR}"
echo "OUT DIR          : ${OUT_DIR}"
echo "TMP DIR          : ${TMP_DIR}"
echo "SHARED TMP DIR   : ${SHARED_TMP_DIR}"
echo "TARGET REF FILE  : ${TARGET_REF_FILE}"
echo "TARGET ZAXIS     : ${TARGET_ZAXIS_FILE}"
echo "SOURCE ZAXIS     : ${SOURCE_ZAXIS_FILE}"
echo "SOURCE Z DIM     : ${SOURCE_ZDIM_NAME}"
echo "SOURCE UNITS IN  : ${SOURCE_UNITS_IN}"
echo "SOURCE UNITS OUT : ${SOURCE_UNITS_OUT}"
echo "SOURCE SCALE     : ${SOURCE_SCALE}"
echo "FILE GLOB        : ${FILE_GLOB}"
echo "OUT SUFFIX       : ${OUT_SUFFIX}"
echo "MAX JOBS         : ${MAX_JOBS}"
echo "OVERWRITE        : ${OVERWRITE_OUTPUTS}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Build target z-axis template once, if missing
# ------------------------------------------------------------------------------
if [[ -f "${TARGET_ZAXIS_FILE}" ]]; then
  echo "Using existing target z-axis template:"
  echo "  ${TARGET_ZAXIS_FILE}"
else
  echo "Target z-axis template not found. Creating it now..."
  cdo zaxisdes "${TARGET_REF_FILE}" > "${TARGET_ZAXIS_FILE}"
  echo "Created:"
  echo "  ${TARGET_ZAXIS_FILE}"
fi

# ------------------------------------------------------------------------------
# Build source z-axis descriptor once, if missing
# ------------------------------------------------------------------------------
if [[ -f "${SOURCE_ZAXIS_FILE}" ]]; then
  echo "Using existing source z-axis descriptor:"
  echo "  ${SOURCE_ZAXIS_FILE}"
else
  echo "Source z-axis descriptor not found. Creating it now..."

  FIRST_FILE="$(find "${IN_DIR}" -maxdepth 1 -type f -name "${FILE_GLOB}" | sort | head -n 1)"
  if [[ -z "${FIRST_FILE}" ]]; then
    echo "ERROR: Could not find any input file in: ${IN_DIR}"
    exit 1
  fi

  LEVELS_RAW="$(cdo showlevel "${FIRST_FILE}" | tr ' ' '\n' | awk 'NF')"
  NLEVELS="$(printf "%s\n" "${LEVELS_RAW}" | wc -l | awk '{print $1}')"

  if [[ "${SOURCE_SCALE}" == "1" ]]; then
    LEVELS_OUT="$(printf "%s\n" "${LEVELS_RAW}" | awk 'NF{printf "%s ", $1}')"
  else
    LEVELS_OUT="$(printf "%s\n" "${LEVELS_RAW}" | awk -v s="${SOURCE_SCALE}" 'NF{printf "%s ", $1*s}')"
  fi

  cat > "${SOURCE_ZAXIS_FILE}" <<EOF
zaxistype = generic
size      = ${NLEVELS}
name      = ${SOURCE_ZDIM_NAME}
longname  = ocean depth
units     = ${SOURCE_UNITS_OUT}
levels    = ${LEVELS_OUT}
EOF

  echo "Created:"
  echo "  ${SOURCE_ZAXIS_FILE}"
fi

process_one_file() {
  local infile="$1"
  local base tmpfile outfile

  base="$(basename "${infile}" .nc)"
  tmpfile="${TMP_DIR}/${base}_zfix.nc"
  outfile="${OUT_DIR}/${base}_${OUT_SUFFIX}.nc"

  echo
  echo "[START] ${base}"

  if [[ -f "${outfile}" ]]; then
    if [[ "${OVERWRITE_OUTPUTS}" == "yes" ]]; then
      echo "[INFO ] Replacing existing output: ${outfile}"
      rm -f "${outfile}"
    else
      echo "[SKIP ] Output already exists: ${outfile}"
      return 0
    fi
  fi

  if [[ -f "${tmpfile}" ]]; then
    echo "[WARN ] Removing stale temp file: ${tmpfile}"
    rm -f "${tmpfile}"
  fi

  echo "[STEP1] Setting source z-axis and units"
  cdo setattribute,${SOURCE_ZDIM_NAME}@units="${SOURCE_UNITS_OUT}" \
    -setzaxis,"${SOURCE_ZAXIS_FILE}" \
    "${infile}" "${tmpfile}"

  echo "[STEP2] Interpolating vertically onto target levels"
  cdo intlevel,zdescription="${TARGET_ZAXIS_FILE}" "${tmpfile}" "${outfile}"

  echo "[STEP3] Cleaning temp file"
  rm -f "${tmpfile}"

  echo "[DONE ] ${outfile}"
}

export TMP_DIR OUT_DIR TARGET_ZAXIS_FILE SOURCE_ZAXIS_FILE SOURCE_ZDIM_NAME SOURCE_UNITS_OUT OUT_SUFFIX OVERWRITE_OUTPUTS
export -f process_one_file

FILES=( "${IN_DIR}"/${FILE_GLOB} )
REAL_FILES=()
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  REAL_FILES+=( "$f" )
done

if [[ ${#REAL_FILES[@]} -eq 0 ]]; then
  echo "ERROR: No input files found in ${IN_DIR}"
  exit 1
fi

echo "Found ${#REAL_FILES[@]} input files."

running=0
for f in "${REAL_FILES[@]}"; do
  process_one_file "${f}" &
  ((running+=1))

  if (( running >= MAX_JOBS )); then
    wait -n
    ((running-=1))
  fi
done

wait

echo
echo "All vertical interpolation processing completed for DATASET=${DATASET_LABEL}"
