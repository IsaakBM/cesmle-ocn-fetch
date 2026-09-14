#!/bin/bash
#
# ==============================================================================
#  Generic temporal aggregation + regridder
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Build monthly means from daily files organized as YEAR/MONTH
#    - Or skip temporal aggregation when inputs are already monthly
#    - Or regrid one-or-more monthly time-series files directly
#    - Process one variable (VAR) using either YEAR/MONTH or time-series input
#    - Regrid outputs to a target lon/lat grid using a chosen CDO method
#    - Run monthly or file-level work in parallel
#    - Handle temp files safely
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=temporal_regrid
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=512G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/temporal_regrid_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/temporal_regrid_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail

# ==============================================================================
# Required env vars (passed at sbatch time)
#   DATASET_LABEL : short dataset label for logs/messages
#   VAR           : variable to process
#   INROOT        : input root
#   OUTROOT       : output root
#   GRIDFILE      : CDO target grid file
#
# Optional env vars
#   INPUT_LAYOUT  : year_month | timeseries (default: year_month)
#   YEAR          : year to process when INPUT_LAYOUT=year_month
#   FILE_GLOB     : input file glob (default: *.nc*)
#   METHOD        : CDO remapping method or auto (default: remapbil)
#   AUTO_METHOD_DEFAULT     : method used in auto mode for regular grids
#                             (default: remapbil)
#   AUTO_METHOD_CURVILINEAR : method used in auto mode for curvilinear or
#                             unstructured grids (default: remapdis)
#   PARTS_SUBDIR  : output subdir under OUTROOT/VAR (default: parts)
#   TMP_SUBDIR    : temp subdir under OUTROOT/VAR (default: tmp)
#   MIN_FREE_GB   : minimum free space on the output filesystem (default: 40)
#   CDO           : CDO executable (default: /usr/bin/cdo)
#   INPUT_TIMESTEP: daily | monthly | auto (default: auto)
#                   used only for INPUT_LAYOUT=year_month
# ==============================================================================
CDO="${CDO:-/usr/bin/cdo}"
DATASET_LABEL="${DATASET_LABEL:-dataset}"
VAR="${VAR:-}"
YEAR="${YEAR:-}"
INROOT="${INROOT:-}"
OUTROOT="${OUTROOT:-}"
GRIDFILE="${GRIDFILE:-}"

INPUT_LAYOUT="${INPUT_LAYOUT:-year_month}"
FILE_GLOB="${FILE_GLOB:-*.nc*}"
METHOD="${METHOD:-remapbil}"
AUTO_METHOD_DEFAULT="${AUTO_METHOD_DEFAULT:-remapbil}"
AUTO_METHOD_CURVILINEAR="${AUTO_METHOD_CURVILINEAR:-remapdis}"
PARTS_SUBDIR="${PARTS_SUBDIR:-parts}"
TMP_SUBDIR="${TMP_SUBDIR:-tmp}"
MIN_FREE_GB="${MIN_FREE_GB:-40}"
INPUT_TIMESTEP="${INPUT_TIMESTEP:-auto}"

if [[ -z "$VAR" || -z "$INROOT" || -z "$OUTROOT" || -z "$GRIDFILE" ]]; then
  echo "ERROR: Missing required environment variables."
  echo "Required: VAR, INROOT, OUTROOT, GRIDFILE"
  echo "Optional: DATASET_LABEL, INPUT_LAYOUT, YEAR, FILE_GLOB, METHOD, PARTS_SUBDIR, TMP_SUBDIR, MIN_FREE_GB, INPUT_TIMESTEP"
  exit 1
fi

if [[ "$INPUT_LAYOUT" != "year_month" && "$INPUT_LAYOUT" != "timeseries" ]]; then
  echo "ERROR: INPUT_LAYOUT must be one of: year_month, timeseries"
  exit 1
fi

if [[ "$INPUT_TIMESTEP" != "daily" && "$INPUT_TIMESTEP" != "monthly" && "$INPUT_TIMESTEP" != "auto" ]]; then
  echo "ERROR: INPUT_TIMESTEP must be one of: daily, monthly, auto"
  exit 1
fi

if [[ "$METHOD" != "auto" && "$METHOD" != remap* ]]; then
  echo "ERROR: METHOD must be auto or a valid CDO remap operator name"
  exit 1
fi

if [[ "$INPUT_LAYOUT" == "year_month" && -z "$YEAR" ]]; then
  echo "ERROR: YEAR must be set when INPUT_LAYOUT=year_month"
  exit 1
fi

if [[ ! -d "$INROOT" ]]; then
  echo "ERROR: Input root not found: $INROOT"
  exit 1
fi

if [[ ! -f "$GRIDFILE" ]]; then
  echo "ERROR: Grid file not found: $GRIDFILE"
  exit 1
fi

# ==============================================================================
# Paths
# ==============================================================================
OUTDIR="${OUTROOT}/${VAR}"
PARTS="${OUTDIR}/${PARTS_SUBDIR}"
mkdir -p "$PARTS"

LOGDIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"
mkdir -p "$LOGDIR"

# ==============================================================================
# Temp directory
# ==============================================================================
TMPBASE="${SLURM_TMPDIR:-${OUTROOT}/tmp}"
TMP_TAG="${YEAR:-all}"
TMPDIR="${TMPBASE}/${DATASET_LABEL}_${VAR}_${TMP_TAG}_${TMP_SUBDIR}"
mkdir -p "$TMPDIR"

# Replacements live beside final outputs for atomic rename; check that filesystem.
# Free-space preflight
FREE_GB=$(df -BG "$PARTS" | awk 'NR==2 {gsub("G","",$4); print $4}')

if [[ -z "$FREE_GB" ]]; then
  echo "ERROR: Could not determine free space on: $PARTS"
  exit 1
fi

if [[ "$FREE_GB" -lt "$MIN_FREE_GB" ]]; then
  echo "ERROR: Low free space where replacements are written: ${FREE_GB}G free, need at least ${MIN_FREE_GB}G."
  echo "       Path checked: $PARTS"
  exit 1
fi

NPROC="${SLURM_CPUS_PER_TASK:-4}"

echo "================================================="
echo " DATASET        : $DATASET_LABEL"
echo " Input root     : $INROOT"
echo " Input layout   : $INPUT_LAYOUT"
echo " Variable       : $VAR"
if [[ -n "$YEAR" ]]; then
  echo " Year           : $YEAR"
fi
echo " File glob      : $FILE_GLOB"
echo " Output dir     : $OUTDIR"
echo " Parts dir      : $PARTS"
echo " Temp dir       : $TMPDIR"
echo " Grid           : $GRIDFILE"
echo " Method         : $METHOD"
if [[ "$METHOD" == "auto" ]]; then
  echo " Auto regular   : $AUTO_METHOD_DEFAULT"
  echo " Auto curvilin  : $AUTO_METHOD_CURVILINEAR"
fi
echo " Input timestep : $INPUT_TIMESTEP"
echo " CPUs           : ${SLURM_CPUS_PER_TASK:-4}"
echo " Parallel months: $NPROC"
echo " Free tmp fs    : ${FREE_GB}G (min ${MIN_FREE_GB}G)"
echo "================================================="

# ==============================================================================
# Build one month from YEAR/MONTH input
# ==============================================================================
detect_gridtype() {
  local src="$1"
  local gridtype

  gridtype="$("$CDO" -s griddes "$src" 2>/dev/null | awk '$1 == "gridtype" {print $3; exit}')"
  if [[ -z "$gridtype" ]]; then
    gridtype="unknown"
  fi
  printf '%s\n' "$gridtype"
}

resolve_method() {
  local src="$1"
  local gridtype

  if [[ "$METHOD" != "auto" ]]; then
    printf '%s\n' "$METHOD"
    return 0
  fi

  gridtype="$(detect_gridtype "$src")"
  case "$gridtype" in
    curvilinear|unstructured)
      printf '%s\n' "$AUTO_METHOD_CURVILINEAR"
      ;;
    *)
      printf '%s\n' "$AUTO_METHOD_DEFAULT"
      ;;
  esac
}

# ==============================================================================
# Validate actual daily timestamps. Exit 10 means only missing days; other
# failures (including duplicate versions) must be reviewed before downloading.
# ==============================================================================
validate_daily_coverage() {
  python3 - "$@" <<'PY_DAILY_COVERAGE'
import sys
from collections import defaultdict
import cftime
import netCDF4
import numpy as np

year, month = map(int, sys.argv[1:3])
paths = sys.argv[3:]
try:
    seen = defaultdict(list)
    calendar = None
    aliases = {'gregorian': 'standard', '365_day': 'noleap', '366_day': 'all_leap'}
    for path in paths:
        with netCDF4.Dataset(path) as ds:
            if 'time' not in ds.variables:
                raise ValueError(f'{path}: missing time coordinate')
            time = ds.variables['time']
            cal = aliases.get(getattr(time, 'calendar', 'standard'), getattr(time, 'calendar', 'standard'))
            if cal not in ('standard', 'proleptic_gregorian', 'noleap', 'all_leap', '360_day', 'julian'):
                raise ValueError(f'{path}: unsupported calendar {cal}')
            if calendar is not None and calendar != cal:
                raise ValueError('mixed calendars require review')
            calendar = cal
            values = time[:]
            if values.ndim != 1 or not values.size or np.ma.getmaskarray(values).any() or not np.isfinite(values).all():
                raise ValueError(f'{path}: empty, masked, or invalid time coordinate')
            for date in netCDF4.num2date(values, time.units, calendar=cal, only_use_cftime_datetimes=True):
                if (date.year, date.month) != (year, month):
                    raise ValueError(f'{path}: out-of-month timestamp {date}')
                seen[date.day].append(path)
    duplicates = {day: names for day, names in seen.items() if len(names) > 1}
    if duplicates:
        raise ValueError('duplicate days/versions: ' + repr(duplicates))
    if not paths:
        print(f'Missing days: no files for {year:04d}-{month:02d}', file=sys.stderr)
        sys.exit(10)
    first = cftime.datetime(year, month, 1, calendar=calendar)
    # Date construction honors the calendar, including the Gregorian reform gap.
    expected = set()
    for day in range(1, first.daysinmonth + 1):
        try:
            cftime.datetime(year, month, day, calendar=calendar)
            expected.add(day)
        except ValueError:
            pass
    missing = sorted(expected - set(seen))
    if missing:
        print(f'Missing days: {year:04d}-{month:02d}: {missing}', file=sys.stderr)
        sys.exit(10)
    print(f'Validated daily coverage: {year:04d}-{month:02d}, {len(expected)} days ({calendar})')
except Exception as error:
    print(f'Daily coverage validation failed: {error}', file=sys.stderr)
    sys.exit(1)
PY_DAILY_COVERAGE
}

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

# Each child owns an output lock and a private workspace beside the final file.
# Atomic rename cannot cross filesystems. Never remove a pre-existing lock:
# after an uncatchable kill, confirm no writer remains before manual recovery.
process_month() (
  set -euo pipefail
  local yyyy="$1" mm="$2" work=""
  local inpath="${INROOT}/${yyyy}/${mm}"
  local out="${PARTS}/${DATASET_LABEL}_${VAR}_${yyyy}${mm}.monmean.$(basename "$GRIDFILE" .txt).nc"
  local mode="$INPUT_TIMESTEP" method_to_use source_file
  [[ -d "$inpath" ]] || { echo "ERROR: Missing month directory: $inpath" >&2; exit 1; }
  local files=()
  mapfile -t files < <(find "$inpath" -maxdepth 1 -type f -name "$FILE_GLOB" | sort)
  (( ${#files[@]} )) || { echo "ERROR: No files in $inpath" >&2; exit 1; }
  mkdir "${out}.lock" 2>/dev/null || { echo "ERROR: Output locked: $out" >&2; exit 1; }
  PREP_WORK_PATH=""
  PREP_LOCK_PATH="${out}.lock"
  trap '[[ -z "$PREP_WORK_PATH" ]] || rm -rf -- "$PREP_WORK_PATH"; rmdir -- "$PREP_LOCK_PATH"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  work="$(mktemp -d "${out}.work.XXXXXX")"
  PREP_WORK_PATH="$work"
  if [[ "$mode" == "auto" ]]; then
    if (( ${#files[@]} == 1 )); then mode=monthly; else mode=daily; fi
  fi
  if [[ "$mode" == "daily" ]]; then
    validate_daily_coverage "$yyyy" "$mm" "${files[@]}"
    "$CDO" -L -O -P 1 -selname,"${VAR}" -mergetime "${files[@]}" "$work/merge.nc"
    "$CDO" -L -O -P 1 monmean "$work/merge.nc" "$work/month.nc"
  else
    # Preserve the existing monthly selection and numerical calculation.
    "$CDO" -L -O -P 1 -selname,"${VAR}" "${files[0]}" "$work/month.nc"
  fi
  source_file="${files[0]}"
  method_to_use="$(resolve_method "$source_file")"
  "$CDO" -L -O -P 1 ${method_to_use},"${GRIDFILE}" "$work/month.nc" "$work/output.nc"
  validate_prepared_output "$work/output.nc" "$work/month.nc"
  mv -f -- "$work/output.nc" "$out"
  echo "DONE: $out"
  exit 0
)

process_timeseries_file() (
  set -euo pipefail
  local in="$1" base stem out work="" method_to_use
  base="$(basename "$in")"; stem="${base%.nc}"
  out="${PARTS}/${stem}.$(basename "$GRIDFILE" .txt).nc"
  [[ -f "$in" ]] || { echo "ERROR: Missing file: $in" >&2; exit 1; }
  mkdir "${out}.lock" 2>/dev/null || { echo "ERROR: Output locked: $out" >&2; exit 1; }
  PREP_WORK_PATH=""
  PREP_LOCK_PATH="${out}.lock"
  trap '[[ -z "$PREP_WORK_PATH" ]] || rm -rf -- "$PREP_WORK_PATH"; rmdir -- "$PREP_LOCK_PATH"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  work="$(mktemp -d "${out}.work.XXXXXX")"
  PREP_WORK_PATH="$work"
  method_to_use="$(resolve_method "$in")"
  # Select once, so validation compares exactly the variables being regridded.
  "$CDO" -L -O -P 1 -selname,"${VAR}" "$in" "$work/selected.nc"
  "$CDO" -L -O -P 1 ${method_to_use},"${GRIDFILE}" "$work/selected.nc" "$work/output.nc"
  validate_prepared_output "$work/output.nc" "$work/selected.nc"
  mv -f -- "$work/output.nc" "$out"
  echo "DONE: $out"
  exit 0
)

export CDO
export -f validate_daily_coverage validate_prepared_output
export -f detect_gridtype resolve_method process_month process_timeseries_file
export DATASET_LABEL INROOT OUTROOT OUTDIR PARTS TMPDIR VAR GRIDFILE METHOD AUTO_METHOD_DEFAULT AUTO_METHOD_CURVILINEAR FILE_GLOB INPUT_TIMESTEP

# ==============================================================================
# Main
# ==============================================================================
if [[ "$INPUT_LAYOUT" == "year_month" ]]; then
  printf "%s\n" 01 02 03 04 05 06 07 08 09 10 11 12 \
    | xargs -I{} -P "$NPROC" bash -c 'process_month "$@"' _ "$YEAR" {}
else
  mapfile -t TS_FILES < <(find "$INROOT" -maxdepth 1 -type f -name "$FILE_GLOB" | sort)

  if [[ "${#TS_FILES[@]}" -eq 0 ]]; then
    echo "ERROR: No matching time-series files found in: $INROOT"
    exit 1
  fi

  printf "%s\n" "${TS_FILES[@]}" \
    | xargs -I{} -P "$NPROC" bash -c 'process_timeseries_file "$@"' _ {}
fi

echo "All done: ${DATASET_LABEL} ${VAR} ${YEAR} (temporal aggregation + regrid)"
