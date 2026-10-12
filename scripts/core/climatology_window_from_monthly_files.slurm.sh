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
#   FILL_TOP_MISSING: yes | no (default: yes)
#                     after climatology generation, fill missing top layers in
#                     each water column from the first deeper valid layer
#   CLIMATOLOGY_MODE: whole | monthly (default: whole)
#                     whole preserves the existing single-window product;
#                     monthly writes January-December climatologies plus an
#                     auxiliary previous-December climatology
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
FILL_TOP_MISSING="${FILL_TOP_MISSING:-yes}"
CLIMATOLOGY_MODE="${CLIMATOLOGY_MODE:-whole}"

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

if [[ "$FILL_TOP_MISSING" != "yes" && "$FILL_TOP_MISSING" != "no" ]]; then
  echo "ERROR: FILL_TOP_MISSING must be yes or no"
  exit 1
fi

if [[ "$CLIMATOLOGY_MODE" != "whole" && "$CLIMATOLOGY_MODE" != "monthly" ]]; then
  echo "ERROR: CLIMATOLOGY_MODE must be one of: whole, monthly"
  exit 1
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
echo "FILL TOP    : ${FILL_TOP_MISSING}"
echo "CLIM MODE   : ${CLIMATOLOGY_MODE}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Gather files inside the target window
# ------------------------------------------------------------------------------
FILES=( "${IN_DIR}"/${FILE_GLOB} )

VALID_FILES=()
selection_start="${WINDOW_START}"
if [[ "$CLIMATOLOGY_MODE" == "monthly" ]]; then
  selection_start="$((10#${WINDOW_START:0:4} - 1))12"
fi
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue

  bn="$(basename "$f")"
  yyyymm="$(printf "%s\n" "$bn" | grep -oE "${DATE_PATTERN}" | head -n 1 || true)"

  if [[ -z "${yyyymm}" ]]; then
    continue
  fi

  if [[ "${yyyymm}" < "${selection_start}" || "${yyyymm}" > "${WINDOW_END}" ]]; then
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
  echo "      Actual timestamp coverage will be checked before processing."
fi

COVERAGE_INPUTS=( "${VALID_FILES[@]}" )
# ------------------------------------------------------------------------------
# Validate actual monthly timestamps before merging or replacing any output.
# CDO decodes the source calendar; Python counts year/month pairs without forcing
# 360-day or no-leap dates into the Gregorian calendar. Check files separately so
# overlapping chunks cannot hide duplicate months during a later merge.
# ------------------------------------------------------------------------------
python3 - "${selection_start}" "${WINDOW_END}" monthly "${COVERAGE_INPUTS[@]}" <<'PY_MONTHLY_COVERAGE'
import collections
import re
import subprocess
import sys

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
    for path in paths:
        result = subprocess.run(["cdo", "-s", "showtimestamp", path],
                                capture_output=True, text=True, check=True)
        stamps = result.stdout.split()
        if not stamps:
            raise ValueError(f"No decoded timestamps in {path}")
        for stamp in stamps:
            match = re.fullmatch(r"(\d{4,})-(\d{2})-(\d{2})T\d{2}:\d{2}:\d{2}(?:\.\d+)?", stamp)
            if not match:
                raise ValueError(f"Unrecognized timestamp {stamp!r} in {path}")
            date = tuple(map(int, match.groups()))
            if not 1 <= date[1] <= 12 or not 1 <= date[2] <= 31:
                raise ValueError(f"Invalid timestamp {stamp!r} in {path}")
            if first <= date <= last:
                occurrences[date[0] * 12 + date[1] - 1].append(f"{path} ({stamp})")
            elif mode == "monthly":
                # This worker averages entire selected files, so outside-window
                # timesteps must fail rather than enter the mean unnoticed.
                raise ValueError(f"Timestamp outside requested window: {path} ({stamp})")
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
except (ValueError, OSError, subprocess.CalledProcessError) as exc:
    print(f"ERROR: Monthly coverage validation: {exc}", file=sys.stderr)
    if isinstance(exc, subprocess.CalledProcessError) and exc.stderr:
        print(exc.stderr.strip(), file=sys.stderr)
    sys.exit(1)
PY_MONTHLY_COVERAGE

write_climatology_metadata() {
  local path="$1"
  local start_text="$2"
  local end_text="$3"
  local selected_count="$4"
  local product_type="$5"
  local month_number="$6"
  local role="$7"

  python3 - "$path" "$start_text" "$end_text" "$selected_count" "$product_type" "$month_number" "$role" <<'PY_METADATA'
import calendar
import sys

import numpy as np
import xarray as xr

path, start_text, end_text, selected_count, product_type, month_number, role = sys.argv[1:]
if end_text.endswith("-last"):
    year, month = map(int, end_text[:-5].split("-"))
    end_text = f"{year:04d}-{month:02d}-{calendar.monthrange(year, month)[1]:02d}"
start = np.datetime64(start_text)
end = np.datetime64(end_text)
midpoint = start + (end - start) // 2

with xr.open_dataset(path) as ds:
    out = ds.load()
if "time" in out.dims:
    if out.sizes["time"] != 1:
        raise ValueError(
            f"Expected singleton climatology time dimension, got {out.sizes['time']}"
        )
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
out.attrs["climatology_selected_timesteps"] = selected_count
if product_type:
    out.attrs["climatology_product_type"] = product_type
if month_number:
    out.attrs["climatology_month"] = int(month_number)
if role:
    out.attrs["climatology_field_role"] = role
out.to_netcdf(path, format="NETCDF4")
PY_METADATA
}

fill_top_layers() {
  local infile="$1"
  local outfile="$2"

  python3 - "$infile" "$outfile" "$VAR" <<'PY_FILL_TOP'
import sys

import numpy as np
import xarray as xr

infile, outfile, var_hint = sys.argv[1:]
ds = xr.open_dataset(infile)

def pick_main_var(dataset, hint):
    if hint in dataset.data_vars:
        return hint
    candidates = [
        name for name in dataset.data_vars
        if "bnds" not in name.lower() and "bounds" not in name.lower()
    ]
    if not candidates:
        raise ValueError(f"No valid data variable found in dataset: {list(dataset.data_vars)}")
    return candidates[0]

main_var = pick_main_var(ds, var_hint)
da = ds[main_var]
zdim_names = ("depth", "depth_below_sea", "lev", "z_t")
zdim_candidates = [dimension for dimension in da.dims if dimension.lower() in zdim_names]

filled_top_count = 0
first_valid_index = None

if zdim_candidates:
    zdim = zdim_candidates[0]
    other_dims = [dimension for dimension in da.dims if dimension != zdim]
    if other_dims:
        transposed = da.transpose(zdim, *other_dims)
        values = transposed.values
        nlev = values.shape[0]
        flat = values.reshape(nlev, -1)

        first_valid_indices = np.full(flat.shape[1], -1, dtype=int)
        for column in range(flat.shape[1]):
            valid = np.where(np.isfinite(flat[:, column]))[0]
            if valid.size > 0:
                first_valid_indices[column] = int(valid[0])

        for column in range(flat.shape[1]):
            donor_index = first_valid_indices[column]
            if donor_index <= 0:
                continue
            donor_value = flat[donor_index, column]
            for level_index in range(donor_index):
                if not np.isfinite(flat[level_index, column]):
                    flat[level_index, column] = donor_value
                    filled_top_count += 1

        filled_values = flat.reshape(values.shape)
        filled = xr.DataArray(
            filled_values,
            coords=transposed.coords,
            dims=transposed.dims,
            attrs=da.attrs,
            name=da.name,
        ).transpose(*da.dims)

        valid_indices = first_valid_indices[first_valid_indices >= 0]
        if valid_indices.size > 0:
            first_valid_index = int(valid_indices.min())

        ds[main_var] = filled
else:
    zdim = None

encoding = {main_var: {"zlib": True, "complevel": 1}}
print(f"MAIN VAR           : {main_var}")
print(f"VERTICAL DIM       : {zdim}")
print(f"FIRST VALID INDEX  : {first_valid_index}")
print(f"TOP LEVELS FILLED  : {filled_top_count}")
ds.to_netcdf(outfile, format="NETCDF4", encoding=encoding)
ds.close()
PY_FILL_TOP
}

if [[ "$CLIMATOLOGY_MODE" == "monthly" ]]; then
  start_year="${WINDOW_START:0:4}"
  end_year="${WINDOW_END:0:4}"
  expected_per_field=$((10#${end_year} - 10#${start_year} + 1))
  previous_start_year=$((10#${start_year} - 1))
  previous_end_year=$((10#${end_year} - 1))
  monthly_temps=()
  monthly_outputs=()

  echo "[STEP1] Computing twelve calendar-month climatologies"
  for month in {1..12}; do
    month_padded="$(printf '%02d' "$month")"
    month_files=()
    for input_file in "${VALID_FILES[@]}"; do
      filename="$(basename "$input_file")"
      yyyymm="$(printf '%s\n' "$filename" | grep -oE "${DATE_PATTERN}" | head -n 1 || true)"
      year="${yyyymm:0:4}"
      input_month="${yyyymm:4:2}"
      if [[ "$year" -ge "$start_year" && "$year" -le "$end_year" && "$input_month" == "$month_padded" ]]; then
        month_files+=( "$input_file" )
      fi
    done
    if [[ "${#month_files[@]}" -ne "$expected_per_field" ]]; then
      echo "ERROR: Month ${month_padded} expected ${expected_per_field} files, found ${#month_files[@]}" >&2
      exit 1
    fi

    monthly_tmp="${TMP_DIR}/${OUT_PREFIX}_clim_month_${month_padded}_${start_year}-${end_year}.tmp.nc"
    monthly_filled="${TMP_DIR}/${OUT_PREFIX}_clim_month_${month_padded}_${start_year}-${end_year}.filled.tmp.nc"
    monthly_out="${OUT_DIR}/${OUT_PREFIX}_clim_month_${month_padded}_${start_year}-${end_year}.nc"
    rm -f "$monthly_tmp" "$monthly_filled"
    cdo -L -O timmean -mergetime "${month_files[@]}" "$monthly_tmp"
    write_climatology_metadata "$monthly_tmp" \
      "${start_year}-${month_padded}-01" "${end_year}-${month_padded}-last" \
      "${#month_files[@]}" "monthly" "$month" "calendar_month"
    if [[ "$FILL_TOP_MISSING" == "yes" ]]; then
      fill_top_layers "$monthly_tmp" "$monthly_filled"
      mv -f "$monthly_filled" "$monthly_tmp"
    fi
    monthly_temps+=( "$monthly_tmp" )
    monthly_outputs+=( "$monthly_out" )
  done

  previous_files=()
  for input_file in "${VALID_FILES[@]}"; do
    filename="$(basename "$input_file")"
    yyyymm="$(printf '%s\n' "$filename" | grep -oE "${DATE_PATTERN}" | head -n 1 || true)"
    year="${yyyymm:0:4}"
    input_month="${yyyymm:4:2}"
    if [[ "$year" -ge "$previous_start_year" && "$year" -le "$previous_end_year" && "$input_month" == "12" ]]; then
      previous_files+=( "$input_file" )
    fi
  done
  if [[ "${#previous_files[@]}" -ne "$expected_per_field" ]]; then
    echo "ERROR: Previous December expected ${expected_per_field} files, found ${#previous_files[@]}" >&2
    exit 1
  fi

  previous_tmp="${TMP_DIR}/${OUT_PREFIX}_clim_previous_december_${start_year}-${end_year}.tmp.nc"
  previous_filled="${TMP_DIR}/${OUT_PREFIX}_clim_previous_december_${start_year}-${end_year}.filled.tmp.nc"
  previous_out="${OUT_DIR}/${OUT_PREFIX}_clim_previous_december_${start_year}-${end_year}.nc"
  rm -f "$previous_tmp" "$previous_filled"
  cdo -L -O timmean -mergetime "${previous_files[@]}" "$previous_tmp"
  write_climatology_metadata "$previous_tmp" \
    "${previous_start_year}-12-01" "${previous_end_year}-12-31" \
    "${#previous_files[@]}" "monthly" "12" "previous_december"
  if [[ "$FILL_TOP_MISSING" == "yes" ]]; then
    fill_top_layers "$previous_tmp" "$previous_filled"
    mv -f "$previous_filled" "$previous_tmp"
  fi
  monthly_temps+=( "$previous_tmp" )
  monthly_outputs+=( "$previous_out" )

  echo "[STEP2] Publishing all 13 monthly climatology fields"
  for index in "${!monthly_temps[@]}"; do
    mv -f "${monthly_temps[$index]}" "${monthly_outputs[$index]}"
    echo "[DONE ] ${monthly_outputs[$index]}"
  done

  echo
  echo "All 13 monthly climatology fields completed for VAR=${VAR}"
  exit 0
fi

# ------------------------------------------------------------------------------
# Output names
# ------------------------------------------------------------------------------
OUTFILE="${OUT_DIR}/${OUT_PREFIX}_clim_${WINDOW_START:0:4}-${WINDOW_END:0:4}.nc"
TMP_OUT="${TMP_DIR}/${OUT_PREFIX}_clim_${WINDOW_START:0:4}-${WINDOW_END:0:4}.tmp.nc"
TMP_FILLED="${TMP_DIR}/${OUT_PREFIX}_clim_${WINDOW_START:0:4}-${WINDOW_END:0:4}.filled.tmp.nc"

# ------------------------------------------------------------------------------
# Processing
# ------------------------------------------------------------------------------
echo "[STEP1] Clearing temporary files; retaining existing output until replacement succeeds"
rm -f "${TMP_OUT}" "${TMP_FILLED}"

echo "[STEP2] Computing climatological mean directly from monthly files"
cdo -L -O timmean -mergetime "${VALID_FILES[@]}" "${TMP_OUT}"

write_climatology_metadata "$TMP_OUT" \
  "${WINDOW_START:0:4}-${WINDOW_START:4:2}-01" \
  "${WINDOW_END:0:4}-${WINDOW_END:4:2}-28" \
  "${#VALID_FILES[@]}" "" "" ""

if [[ "$FILL_TOP_MISSING" == "yes" ]]; then
  echo "[STEP3] Filling missing top climatology layers dynamically"
  fill_top_layers "$TMP_OUT" "$TMP_FILLED"
  mv -f "${TMP_FILLED}" "${TMP_OUT}"
fi

echo "[STEP4] Writing final output"
mv -f "${TMP_OUT}" "${OUTFILE}"

echo "[DONE ] ${OUTFILE}"
echo
echo "All climatology window processing completed for VAR=${VAR}"
