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
#    - Compute the existing whole-window climatology, 12 monthly climatology
#      fields, or four calendar-weighted seasonal climatology fields
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
#   CLIMATOLOGY_MODE: whole | monthly | seasonal (default: whole)
#                     whole preserves the existing single-window product;
#                     monthly writes January-December climatologies; seasonal
#                     writes DJF, MAM, JJA, and SON climatologies and consumes
#                     the preceding December required by DJF
#   CLIM_WORKERS    : concurrent seasonal fields (default: allocated CPUs,
#                     capped at four); monthly means use one streamed CDO pass
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
CLIMATOLOGY_MODE="${CLIMATOLOGY_MODE:-whole}"
CLIM_WORKERS="${CLIM_WORKERS:-${SLURM_CPUS_PER_TASK:-1}}"
if ! [[ "$CLIM_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: CLIM_WORKERS must be a positive integer" >&2
  exit 1
fi
if (( CLIM_WORKERS > ${SLURM_CPUS_PER_TASK:-$CLIM_WORKERS} )); then
  echo "ERROR: CLIM_WORKERS exceeds allocated CPUs" >&2
  exit 1
fi
(( CLIM_WORKERS <= 4 )) || CLIM_WORKERS=4
if [[ "$CLIMATOLOGY_MODE" != whole ]]; then
  export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
  python3 -c 'import netCDF4, numpy'
fi

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

if [[ "$CLIMATOLOGY_MODE" != "whole" && "$CLIMATOLOGY_MODE" != "monthly" && "$CLIMATOLOGY_MODE" != "seasonal" ]]; then
  echo "ERROR: CLIMATOLOGY_MODE must be one of: whole, monthly, seasonal"
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
echo "CLIM MODE    : ${CLIMATOLOGY_MODE}"
echo "============================================================"

OUTFILE="${OUT_DIR}/${OUT_PREFIX}_clim_${WINDOW_START:0:4}-${WINDOW_END:0:4}.nc"
TMP_MERGED="${TMP_DIR}/${OUT_PREFIX}_merged_${WINDOW_START:0:4}-${WINDOW_END:0:4}.tmp.nc"
TMP_SEL="${TMP_DIR}/${OUT_PREFIX}_sel_${WINDOW_START:0:4}-${WINDOW_END:0:4}.tmp.nc"
TMP_OUT="${TMP_DIR}/${OUT_PREFIX}_clim_${WINDOW_START:0:4}-${WINDOW_END:0:4}.tmp.nc"

INPUT_MODE="$MERGE_INPUTS"
if [[ "$INPUT_MODE" == "auto" ]]; then
  if [[ ${#REAL_INPUTS[@]} -gt 1 ]]; then
    INPUT_MODE="yes"
  else
    INPUT_MODE="no"
  fi
fi

# Validate precisely the files that the existing merge policy will consume.
COVERAGE_INPUTS=( "${REAL_INPUTS[@]}" )
if [[ "$INPUT_MODE" == "no" ]]; then
  COVERAGE_INPUTS=( "${REAL_INPUTS[0]}" )
fi
# ------------------------------------------------------------------------------
# Validate actual monthly timestamps before merging or replacing any output.
# CDO decodes the source calendar; Python counts year/month pairs without forcing
# 360-day or no-leap dates into the Gregorian calendar. Check files separately so
# overlapping chunks cannot hide duplicate months during a later merge.
# ------------------------------------------------------------------------------
coverage_start="${WINDOW_START}"
coverage_end="${WINDOW_END}"
if [[ "$CLIMATOLOGY_MODE" == "seasonal" ]]; then
  coverage_start="$((10#${WINDOW_START:0:4} - 1))-12-01"
  coverage_end="${WINDOW_END:0:4}-11-30"
fi

coverage_report="$(python3 - "${coverage_start}" "${coverage_end}" timeseries "${COVERAGE_INPUTS[@]}" <<'PY_MONTHLY_COVERAGE'
import collections
import re
import subprocess
import sys
import calendar

start, end, mode, *paths = sys.argv[1:]

def window_date(value, last=False):
    pattern = r"(\d{4})(\d{2})" if mode == "monthly" else r"(\d{4})-(\d{2})-(\d{2})"
    match = re.fullmatch(pattern, value)
    if not match:
        raise ValueError(f"Invalid window date: {value}")
    parts = tuple(map(int, match.groups()))
    year, month = parts[:2]
    day = parts[2] if len(parts) == 3 else (31 if last else 1)
    if year < 1 or not 1 <= month <= 12 or not 1 <= day <= 31:
        raise ValueError(f"Invalid window date: {value}")
    return year, month, day

try:
    first, last = window_date(start), window_date(end, last=True)
    if first > last:
        raise ValueError("WINDOW_START is after WINDOW_END")
    # Integer month indices work for all supported source calendars.
    expected = set(range(first[0] * 12 + first[1] - 1,
                         last[0] * 12 + last[1]))
    occurrences = collections.defaultdict(list)
    selected_paths = []
    for path in paths:
        result = subprocess.run(["cdo", "-s", "showtimestamp", path],
                                capture_output=True, text=True, check=True)
        stamps = result.stdout.split()
        if not stamps:
            raise ValueError(f"No decoded timestamps in {path}")
        contributes = False
        for stamp in stamps:
            match = re.fullmatch(r"(\d{4,})-(\d{2})-(\d{2})T\d{2}:\d{2}:\d{2}(?:\.\d+)?", stamp)
            if not match:
                raise ValueError(f"Unrecognized timestamp {stamp!r} in {path}")
            date = tuple(map(int, match.groups()))
            if not 1 <= date[1] <= 12 or not 1 <= date[2] <= 31:
                raise ValueError(f"Invalid timestamp {stamp!r} in {path}")
            if first <= date <= last:
                contributes = True
                occurrences[date[0] * 12 + date[1] - 1].append(f"{path} ({stamp})")
            elif mode == "monthly":
                # This worker averages entire selected files, so outside-window
                # timesteps must fail rather than enter the mean unnoticed.
                raise ValueError(f"Timestamp outside requested window: {path} ({stamp})")
        if contributes:
            selected_paths.append(path)
    label = lambda month: f"{month // 12:04d}-{month % 12 + 1:02d}"
    missing = sorted(expected - occurrences.keys())
    duplicates = sorted(month for month, sources in occurrences.items() if len(sources) > 1)
    if missing or duplicates:
        if missing:
            print("ERROR: Missing months: " + ", ".join(map(label, missing)), file=sys.stderr)
        for month in duplicates:
            print(f"ERROR: Duplicate month {label(month)}: " + "; ".join(occurrences[month]), file=sys.stderr)
        raise ValueError("Monthly coverage failed; existing climatology output was not replaced")
    print(f"MONTHLY COVERAGE: PASS ({len(expected)} months, exactly one timestep per month)")
    for path in selected_paths:
        print("SOURCE CHUNK: " + path)
except (ValueError, OSError, subprocess.CalledProcessError) as exc:
    print(f"ERROR: Monthly coverage validation: {exc}", file=sys.stderr)
    if isinstance(exc, subprocess.CalledProcessError) and exc.stderr:
        print(exc.stderr.strip(), file=sys.stderr)
    sys.exit(1)
PY_MONTHLY_COVERAGE
)"
printf '%s\n' "$coverage_report"
SELECTED_INPUTS=()
while IFS= read -r line; do
  if [[ "$line" == "SOURCE CHUNK: "* ]]; then
    SELECTED_INPUTS+=( "${line#SOURCE CHUNK: }" )
  fi
done <<< "$coverage_report"

echo "[STEP1] Clearing temporary files; retaining existing output until replacement succeeds"
rm -f "${TMP_MERGED}" "${TMP_SEL}" "${TMP_OUT}"

if [[ "$CLIMATOLOGY_MODE" == whole ]]; then
  if [[ "$INPUT_MODE" == "yes" ]]; then
    echo "[STEP2] Merging input files in time"
    cdo -L -O mergetime "${REAL_INPUTS[@]}" "${TMP_MERGED}"
    SOURCE_FILE="${TMP_MERGED}"
  else
    echo "[STEP2] Using single input file without merge"
    SOURCE_FILE="${REAL_INPUTS[0]}"
  fi

  echo "[STEP3] Selecting climatology window"
  selection_start="${WINDOW_START}"
  selection_end="${WINDOW_END}"
  cdo -L -O seldate,"${selection_start}","${selection_end}" "${SOURCE_FILE}" "${TMP_SEL}"
  selected_steps="$(cdo -s ntime "${TMP_SEL}" | tr -d '[:space:]')"
  if [[ -z "${selected_steps}" || "${selected_steps}" -eq 0 ]]; then
    echo "ERROR: No timesteps selected for window ${WINDOW_START} to ${WINDOW_END} from ${SOURCE_FILE}" >&2
    exit 1
  fi
  echo "SELECTED STEPS : ${selected_steps}"

else
  # Coverage already checks decoded timestamps in every source chunk. Read only
  # contributing chunks, and stream their merge through selection. Never write
  # the full merged multi-decade series for monthly/seasonal products.
  if (( ${#SELECTED_INPUTS[@]} == 1 )); then
    SOURCE_ARGS=( "${SELECTED_INPUTS[0]}" )
  else
    SOURCE_ARGS=( -mergetime "${SELECTED_INPUTS[@]}" )
  fi
  echo "[STEP2] Using ${#SELECTED_INPUTS[@]} contributing source chunks"
  selection_start="$coverage_start"
  selection_end="$coverage_end"
  if [[ "$CLIMATOLOGY_MODE" == seasonal ]]; then
    echo "[STEP3] Streaming the seasonal window to compressed temporary storage"
    cdo -L -O -P 1 -f nc4c -z zip_1 seldate,"${selection_start}","${selection_end}" "${SOURCE_ARGS[@]}" "$TMP_SEL"
    selected_steps="$(cdo -s ntime "$TMP_SEL" | tr -d '[:space:]')"
    expected_steps=$(( (10#${WINDOW_END:0:4} - 10#${WINDOW_START:0:4} + 1) * 12 ))
    if [[ "$selected_steps" -ne "$expected_steps" ]]; then
      echo "ERROR: Selected seasonal window has ${selected_steps} steps, expected ${expected_steps}" >&2
      exit 1
    fi
  fi
fi

write_climatology_metadata() {
  local path="$1"
  local start_text="$2"
  local end_text="$3"
  local selected_count="$4"
  local product_type="$5"
  local month_number="$6"
  local role="$7"
  local season_name="$8"
  local season_year_count="$9"

  if [[ -n "$product_type" ]]; then
    # CDO writes compressed temp files. Only time coordinates/attributes are
    # changed here; do not load or rewrite the scientific array.
    python3 - "$path" "$start_text" "$end_text" "$selected_count" "$product_type" "$month_number" "$role" "$season_name" "$season_year_count" <<'PY_FINALIZE'
import calendar
import datetime as dt
import sys

import netCDF4 as nc

path, start_text, end_text, count, kind, month, role, season, years = sys.argv[1:]
if end_text.endswith("-last"):
    year, mon = map(int, end_text[:-5].split("-"))
    end_text = f"{year:04d}-{mon:02d}-{calendar.monthrange(year, mon)[1]:02d}"
start, end = map(dt.datetime.fromisoformat, (start_text, end_text))
midpoint = start + dt.timedelta(days=(end - start).days // 2)
units = f"days since {start.year}-01-01 00:00:00"
cal = "proleptic_gregorian"
expected_month = int(month) if kind == "monthly" else {"DJF": 1, "MAM": 4, "JJA": 7, "SON": 10}[season]
if midpoint.month != expected_month:
    raise ValueError("Climatology midpoint is outside the expected month")
with nc.Dataset(path, "r+") as ds:
    if "time" not in ds.dimensions or len(ds.dimensions["time"]) != 1:
        raise ValueError("Expected singleton climatology time dimension")
    if "bnds" not in ds.dimensions:
        ds.createDimension("bnds", 2)
    if len(ds.dimensions["bnds"]) != 2:
        raise ValueError("Expected two climatology bounds")
    if "time_bnds" not in ds.variables:
        ds.createVariable("time_bnds", "f8", ("time", "bnds"))
    bounds, time = ds.variables["time_bnds"], ds.variables["time"]
    if bounds.dimensions != ("time", "bnds"):
        raise ValueError("Incorrect time_bnds dimensions")
    for variable in (time, bounds):
        variable.setncatts({"units": units, "calendar": cal})
    if "bounds" in time.ncattrs():
        time.delncattr("bounds")
    time.setncatts({"long_name": "climatology time", "climatology": "time_bnds"})
    time[:] = nc.date2num([midpoint], units, cal)
    bounds[:] = nc.date2num([[start, end]], units, cal)
    attrs = {"climatology_window_start": start_text, "climatology_window_end": end_text,
             "climatology_selected_timesteps": count, "climatology_product_type": kind,
             "climatology_field_role": role,
             "climatology_time_policy": "time is the midpoint of time_bnds; time_bnds stores the first and last contributing climatology dates"}
    if month:
        attrs["climatology_month"] = int(month)
    if season:
        attrs.update(climatology_season=season, climatology_season_years=years,
                     climatology_weighting="source-calendar month length within each season year; equal weight across season years")
    ds.setncatts(attrs)
with nc.Dataset(path) as ds:
    time, bounds = ds.variables["time"], ds.variables["time_bnds"]
    actual = nc.num2date(bounds[:].ravel(), bounds.units, bounds.calendar)
    if [(v.year, v.month, v.day) for v in actual] != [(v.year, v.month, v.day) for v in (start, end)]:
        raise ValueError("Serialized climatology bounds differ from requested dates")
    decoded = nc.num2date(time[:], time.units, time.calendar)[0]
    if decoded.month != expected_month or not bounds[0, 0] <= time[0] <= bounds[0, 1]:
        raise ValueError("Invalid serialized climatology time")
    if time.climatology != "time_bnds" or time.units != bounds.units or time.calendar != bounds.calendar:
        raise ValueError("Inconsistent time metadata")
print(f"[READY] {kind} {month or season}", flush=True)
PY_FINALIZE
    return
  fi

  python3 - "$path" "$start_text" "$end_text" "$selected_count" "$product_type" "$month_number" "$role" "$season_name" "$season_year_count" <<'PY_METADATA'
import sys

import numpy as np
import xarray as xr

(path, start_text, end_text, count, *_rest) = sys.argv[1:]
start, end = np.datetime64(start_text), np.datetime64(end_text)
midpoint = start + (end - start) // 2
with xr.open_dataset(path) as ds:
    out = ds.load()
if "time" in out.dims:
    if out.sizes["time"] != 1:
        raise ValueError("Expected singleton climatology time dimension")
    out = out.assign_coords(time=("time", np.array([midpoint], dtype="datetime64[ns]")))
else:
    out = out.expand_dims(time=np.array([midpoint], dtype="datetime64[ns]"))
attrs = dict(out["time"].attrs)
attrs.update({"long_name": "climatology time", "climatology": "time_bnds"})
out["time"].attrs = attrs
out["time_bnds"] = xr.DataArray(
    np.array([[start, end]], dtype="datetime64[ns]"),
    coords={"time": out["time"], "bnds": [0, 1]},
    dims=("time", "bnds"),
)
out.attrs["climatology_window_start"] = start_text
out.attrs["climatology_window_end"] = end_text
out.attrs["climatology_selected_timesteps"] = count
# Preserve the established whole-window encoding exactly.
out.to_netcdf(path, format="NETCDF4")

PY_METADATA
}

if [[ "$CLIMATOLOGY_MODE" == "monthly" ]]; then
  start_year="${WINDOW_START:0:4}"
  end_year="${WINDOW_END:0:4}"
  expected_per_field=$((10#${end_year} - 10#${start_year} + 1))
  monthly_temps=()
  monthly_outputs=()

  split_prefix="${TMP_DIR}/${OUT_PREFIX}_split_month_${start_year}-${end_year}_"
  # Remove only this window's scratch names so a failed retry cannot reuse an
  # incomplete split. Final products are retained until all 12 replacements pass.
  for month in {1..12}; do
    month_padded="$(printf '%02d' "$month")"
    rm -f "${split_prefix}${month_padded}.nc"
  done
  echo "[STEP3] Computing all twelve monthly means in one CDO pass $(date -u +%FT%TZ)"
  cdo -L -O -P 1 -f nc4c -z zip_1 splitmon -ymonmean \
    -seldate,"${selection_start}","${selection_end}" "${SOURCE_ARGS[@]}" "$split_prefix"

  for month in {1..12}; do
    month_padded="$(printf '%02d' "$month")"
    monthly_tmp="${TMP_DIR}/${OUT_PREFIX}_clim_month_${month_padded}_${start_year}-${end_year}.tmp.nc"
    monthly_out="${OUT_DIR}/${OUT_PREFIX}_clim_month_${month_padded}_${start_year}-${end_year}.nc"
    mv -f "${split_prefix}${month_padded}.nc" "$monthly_tmp"
    # Exact observations/year were checked from decoded source timestamps before
    # reduction. The finalizer verifies each reduced field has singleton time.
    write_climatology_metadata "$monthly_tmp" \
      "${start_year}-${month_padded}-01" "${end_year}-${month_padded}-last" \
      "$expected_per_field" "monthly" "$month" "calendar_month" "" ""
    monthly_temps+=( "$monthly_tmp" )
    monthly_outputs+=( "$monthly_out" )
  done

  echo "[STEP5] Publishing all 12 monthly climatology fields"
  for index in "${!monthly_temps[@]}"; do
    mv -f "${monthly_temps[$index]}" "${monthly_outputs[$index]}"
    echo "[DONE ] ${monthly_outputs[$index]}"
  done

  rm -f "${TMP_MERGED}" "${TMP_SEL}"
  echo
  echo "All 12 monthly climatology fields completed for VAR=${VAR}"
  exit 0
fi

field_pids=()
wait_fields() {
  local pid failed=0
  for pid in "${field_pids[@]-}"; do
    [[ -n "$pid" ]] || continue
    if ! wait "$pid"; then
      echo "ERROR: Climatology task ${pid} failed; outputs will not be published" >&2
      failed=1
    fi
  done
  field_pids=()
  (( failed == 0 ))
}

if [[ "$CLIMATOLOGY_MODE" == "seasonal" ]]; then
  start_year="${WINDOW_START:0:4}"
  end_year="${WINDOW_END:0:4}"
  expected_season_years=$((10#${end_year} - 10#${start_year} + 1))
  seasonal_temps=()
  seasonal_outputs=()

  echo "[STEP4] Computing calendar-weighted season-year means"
  echo "FIELD WORKERS: ${CLIM_WORKERS}"
  process_season() (
    set -euo pipefail
    season="$1"
    echo "[START] season=${season} $(date -u +%FT%TZ)"
    season_year_means=()
    for ((year=10#${start_year}; year<=10#${end_year}; year++)); do
      case "$season" in
        DJF)
          season_months="12,1,2"
          ;;
        MAM)
          season_months="3,4,5"
          ;;
        JJA)
          season_months="6,7,8"
          ;;
        SON)
          season_months="9,10,11"
          ;;
      esac

      season_input="${TMP_DIR}/${OUT_PREFIX}_${season}_${year}.selected.tmp.nc"
      season_year_mean="${TMP_DIR}/${OUT_PREFIX}_${season}_${year}.weighted.tmp.nc"
      rm -f "$season_input" "$season_year_mean"
      if [[ "$season" == "DJF" ]]; then
        season_start="$((year - 1))-12-01"
        # Select through the next month's first day, then exclude that month.
        # All boundary dates are valid for Gregorian, noleap and 360-day inputs.
        season_end="${year}-03-01"
      else
        case "$season" in
          MAM) season_start="${year}-03-01"; season_end="${year}-06-01" ;;
          JJA) season_start="${year}-06-01"; season_end="${year}-09-01" ;;
          SON) season_start="${year}-09-01"; season_end="${year}-12-01" ;;
        esac
      fi
      cdo -L -O -P 1 -f nc4c -z zip_1 yearmonmean -setyear,"${year}" \
        -selmon,"${season_months}" -seldate,"${season_start}","${season_end}" "$TMP_SEL" "$season_year_mean"
      weighted_steps="$(cdo -s ntime "$season_year_mean" | tr -d '[:space:]')"
      if [[ "$weighted_steps" -ne 1 ]]; then
        echo "ERROR: ${season} ${year} expected one weighted season-year mean, found ${weighted_steps}" >&2
        exit 1
      fi
      season_year_means+=( "$season_year_mean" )
    done

    if [[ "${#season_year_means[@]}" -ne "$expected_season_years" ]]; then
      echo "ERROR: ${season} expected ${expected_season_years} season-year means, found ${#season_year_means[@]}" >&2
      exit 1
    fi

    seasonal_tmp="${TMP_DIR}/${OUT_PREFIX}_clim_season_${season}_${start_year}-${end_year}.tmp.nc"
    seasonal_out="${OUT_DIR}/${OUT_PREFIX}_clim_season_${season}_${start_year}-${end_year}.nc"
    rm -f "$seasonal_tmp"
    cdo -L -O -P 1 -f nc4c -z zip_1 timmean -mergetime "${season_year_means[@]}" "$seasonal_tmp"

    case "$season" in
      DJF)
        bounds_start="$((10#${start_year} - 1))-12-01"
        bounds_end="${end_year}-02-last"
        ;;
      MAM)
        bounds_start="${start_year}-03-01"
        bounds_end="${end_year}-05-last"
        ;;
      JJA)
        bounds_start="${start_year}-06-01"
        bounds_end="${end_year}-08-last"
        ;;
      SON)
        bounds_start="${start_year}-09-01"
        bounds_end="${end_year}-11-last"
        ;;
    esac
    write_climatology_metadata "$seasonal_tmp" "$bounds_start" "$bounds_end" \
      "$((expected_season_years * 3))" "seasonal" "" "season" "$season" \
      "$expected_season_years"
    rm -f "${season_year_means[@]}"
    echo "[READY] season=${season} $(date -u +%FT%TZ)"
  )
  for season in DJF MAM JJA SON; do
    seasonal_temps+=( "${TMP_DIR}/${OUT_PREFIX}_clim_season_${season}_${start_year}-${end_year}.tmp.nc" )
    seasonal_outputs+=( "${OUT_DIR}/${OUT_PREFIX}_clim_season_${season}_${start_year}-${end_year}.nc" )
    process_season "$season" &
    field_pids+=( "$!" )
    if (( ${#field_pids[@]} >= CLIM_WORKERS )); then wait_fields; fi
  done
  wait_fields

  echo "[STEP5] Publishing all four seasonal climatology fields"
  for index in "${!seasonal_temps[@]}"; do
    mv -f "${seasonal_temps[$index]}" "${seasonal_outputs[$index]}"
    echo "[DONE ] ${seasonal_outputs[$index]}"
  done
  rm -f "${TMP_MERGED}" "${TMP_SEL}"
  echo
  echo "All four seasonal climatology fields completed for VAR=${VAR}"
  exit 0
fi

echo "[STEP4] Computing climatological mean"
cdo -L -O timmean "${TMP_SEL}" "${TMP_OUT}"

write_climatology_metadata "$TMP_OUT" "$WINDOW_START" "$WINDOW_END" \
  "$selected_steps" "" "" "" "" ""

echo "[STEP5] Writing final output"
mv -f "${TMP_OUT}" "${OUTFILE}"

echo "[DONE ] ${OUTFILE}"
echo
echo "All climatology window processing completed for VAR=${VAR}"
