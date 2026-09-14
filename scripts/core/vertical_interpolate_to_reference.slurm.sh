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
#   CDO                : CDO executable (default: cdo)
# ==============================================================================
CDO="${CDO:-cdo}"
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
# Existing explicit/cache descriptors are read as before; missing descriptors are
# built privately for this invocation, never exposed while partially written.
AXIS_WORK="$(mktemp -d "${TMP_DIR}/axis.XXXXXX")"
cleanup_axes() {
  local pid
  # Wait for remaining workers before removing descriptors they may still need.
  for pid in $(jobs -pr); do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
  rm -rf -- "$AXIS_WORK"
}
trap cleanup_axes EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ -f "$TARGET_ZAXIS_FILE" ]] || TARGET_ZAXIS_FILE="$AXIS_WORK/target.txt"
[[ -f "$SOURCE_ZAXIS_FILE" ]] || SOURCE_ZAXIS_FILE="$AXIS_WORK/source.txt"


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
  "$CDO" zaxisdes "${TARGET_REF_FILE}" > "${TARGET_ZAXIS_FILE}"
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

  LEVELS_RAW="$("$CDO" showlevel "${FIRST_FILE}" | tr ' ' '\n' | awk 'NF')"
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

# Read all output records and verify variable names and unchanged timestamps
# against the immediate input to the spatial operation before publication.
validate_prepared_output() {
  local output="$1" reference="$2" names expected_names times expected_times
  [[ -s "$output" ]] || return 1
  "$CDO" -s infon "$output" >/dev/null || return 1
  names="$("$CDO" -s showname "$output")" || return 1
  expected_names="$("$CDO" -s showname "$reference")" || return 1
  times="$("$CDO" -s showtimestamp "$output")" || return 1
  expected_times="$("$CDO" -s showtimestamp "$reference")" || return 1
  if [[ -z "$names" || -z "$times" || "$names" != "$expected_names" || "$times" != "$expected_times" ]]; then
    echo "ERROR: Replacement variables/time differ from input: $output" >&2
    return 1
  fi
}

process_one_file() (
  set -euo pipefail
  local infile="$1" base outfile work=""
  base="$(basename "$infile" .nc)"
  outfile="${OUT_DIR}/${base}_${OUT_SUFFIX}.nc"
  mkdir "${outfile}.lock" 2>/dev/null || { echo "ERROR: Output locked: $outfile" >&2; exit 1; }
  PREP_WORK_PATH=""
  PREP_LOCK_PATH="${outfile}.lock"
  trap '[[ -z "$PREP_WORK_PATH" ]] || rm -rf -- "$PREP_WORK_PATH"; rmdir -- "$PREP_LOCK_PATH"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ -f "$outfile" && "$OVERWRITE_OUTPUTS" == "no" ]]; then
    echo "[SKIP] Existing output retained (freshness not verified): $outfile"
    exit 0
  fi
  work="$(mktemp -d "${outfile}.work.XXXXXX")"
  PREP_WORK_PATH="$work"
  "$CDO" setattribute,${SOURCE_ZDIM_NAME}@units="${SOURCE_UNITS_OUT}" \
    -setzaxis,"${SOURCE_ZAXIS_FILE}" "$infile" "$work/zfix.nc"
  "$CDO" intlevel,zdescription="${TARGET_ZAXIS_FILE}" "$work/zfix.nc" "$work/output.nc"
  validate_prepared_output "$work/output.nc" "$work/zfix.nc"
  # Compare against the configured descriptor, which may intentionally differ
  # from TARGET_REF_FILE when an explicit target axis is supplied.
  python3 - "$CDO" "$work/output.nc" "$TARGET_ZAXIS_FILE" <<'PY_VALIDATE_LEVELS'
import math
import re
import subprocess
import sys
text = open(sys.argv[3]).read()
match = re.search(r"(?ms)^\s*levels\s*=\s*(.*?)(?=^\s*[A-Za-z_]\w*\s*=|\Z)", text)
if not match:
    raise SystemExit('ERROR: Target descriptor has no explicit levels')
expected = [float(x) for x in match[1].split()]
actual_descriptor = subprocess.check_output([sys.argv[1], '-s', 'zaxisdes', sys.argv[2]], text=True)
actual_match = re.search(r"(?ms)^\s*levels\s*=\s*(.*?)(?=^\s*[A-Za-z_]\w*\s*=|\Z)", actual_descriptor)
if not actual_match:
    raise SystemExit('ERROR: Replacement has no explicit vertical levels')
actual = [float(x) for x in actual_match[1].split()]
if len(actual) != len(expected) or not all(math.isclose(a, b, rel_tol=1e-7, abs_tol=1e-9) for a, b in zip(actual, expected)):
    raise SystemExit('ERROR: Replacement levels differ from configured target axis')
PY_VALIDATE_LEVELS
  mv -f -- "$work/output.nc" "$outfile"
  echo "[DONE] $outfile"
  exit 0
)

export TMP_DIR OUT_DIR TARGET_ZAXIS_FILE SOURCE_ZAXIS_FILE SOURCE_ZDIM_NAME SOURCE_UNITS_OUT OUT_SUFFIX OVERWRITE_OUTPUTS
export CDO TARGET_REF_FILE
export -f validate_prepared_output process_one_file

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

# Wait for every child explicitly: a final bare wait can hide failed workers.
pids=()
failed=0
for f in "${REAL_FILES[@]}"; do
  process_one_file "$f" &
  pids+=("$!")
  if (( ${#pids[@]} >= MAX_JOBS )); then
    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
    pids=()
  fi
done
for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid" || failed=1; done
(( failed == 0 )) || { echo "ERROR: Vertical interpolation workers failed" >&2; exit 1; }
echo "All vertical interpolation processing completed for DATASET=${DATASET_LABEL}"
