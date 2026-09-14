#!/bin/bash
#
#SBATCH --job-name=glorys12v1_daily
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=6                  # parallel months
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys12v1_daily_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys12v1_daily_%j.err

set -euo pipefail

# Activate env so CLI is visible in batch
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
  source "$HOME/miniconda3/etc/profile.d/conda.sh"
  conda activate cmems || true
fi
export PATH="$HOME/.local/bin:$PATH"

# ========= Paths =========
REPO_ROOT="/home/sandbox-sparc/cesmle-ocn-fetch"
OUTROOT="${REPO_ROOT}/glorys12v1"
LOGDIR="${REPO_ROOT}/logs"
mkdir -p "$OUTROOT" "$LOGDIR"

# ========= Dataset IDs (original daily files) =========
DATASET_MY="cmems_mod_glo_phy_my_0.083deg_P1D-m"      # 1993–2020
DATASET_MYINT="cmems_mod_glo_phy_myint_0.083deg_P1D-m" # 2021

# ========= Time window (override at submit time) =========
YEAR_START="${YEAR_START:-1993}"
YEAR_END="${YEAR_END:-2021}"
MONTHS=(01 02 03 04 05 06 07 08 09 10 11 12)

# ========= Parallelism =========
CPUS="${SLURM_CPUS_PER_TASK:-4}"

# ========= Locate copernicusmarine CLI =========
CM="${CM:-$(command -v copernicusmarine || true)}"
if [[ -z "$CM" && -x "$HOME/.local/bin/copernicusmarine" ]]; then
  CM="$HOME/.local/bin/copernicusmarine"
fi
if [[ -z "$CM" ]]; then
  echo "[fatal] copernicusmarine CLI not found. Install/login first."
  exit 1
fi

echo "[info] Using CLI: $CM"
echo "[info] Output root: $OUTROOT"
echo "[info] Logs: $LOGDIR"
echo "[info] Parallel workers (months): $CPUS"

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

# Existing nested versions are reported, never flattened or selected implicitly.
check_flat_download_layout() {
  local nested
  nested="$(find "$1" -mindepth 2 -type f -name '*.nc' -print -quit)"
  if [[ -n "$nested" ]]; then
    echo "ERROR: Nested download requires layout/version review: $nested" >&2
    return 1
  fi
}

# ========= Build per-month tasks =========
TASKS="$(mktemp)"; : > "$TASKS"
trap 'rm -f "$TASKS"' EXIT

for year in $(seq "${YEAR_START}" "${YEAR_END}"); do
  for mm in "${MONTHS[@]}"; do
    # choose dataset by year
    if (( year <= 2020 )); then
      DATASET="$DATASET_MY"
    elif (( year == 2021 )); then
      DATASET="$DATASET_MYINT"
    else
      continue
    fi

    OUTDIR="${OUTROOT}/${year}/${mm}"
    mkdir -p "$OUTDIR"

    # daily filename regex for that month
    REGEX="mercatorglorys12v1_gl12_mean_${year}${mm}[0-9]{2}_R[0-9]{8}\\.nc"

    check_flat_download_layout "$OUTDIR"
    # Only a complete, readable daily time axis qualifies for skipping.
    files=()
    while IFS= read -r -d '' file; do files+=("$file"); done < <(find "$OUTDIR" -maxdepth 1 -type f -name '*.nc' -print0)
    if validate_daily_coverage "$year" "$mm" ${files[@]+"${files[@]}"}; then
      echo "[skip] Verified daily coverage: ${year}-${mm}"
      continue
    else
      status=$?
      [[ "$status" == 10 ]] || exit "$status"
    fi

    echo "${DATASET}|${REGEX}|${OUTDIR}" >> "$TASKS"
  done
done

# ========= Worker =========
fetch_month() (
  set -euo pipefail
  local dataset="$1"
  local regex="$2"
  local outdir="$3"

  # Do not let two downloader instances modify the same month concurrently.
  mkdir "${outdir}.download.lock" 2>/dev/null || { echo "ERROR: Download locked: $outdir" >&2; exit 1; }
  DOWNLOAD_LOCK_PATH="${outdir}.download.lock"
  DOWNLOAD_MANIFEST_TMP=""
  trap '[[ -z "$DOWNLOAD_MANIFEST_TMP" ]] || rm -f -- "$DOWNLOAD_MANIFEST_TMP"; rmdir -- "$DOWNLOAD_LOCK_PATH"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  local year mm manifest
  year=$(basename "$(dirname "$outdir")")
  mm=$(basename "$outdir")
  check_flat_download_layout "$outdir"
  local files=()
  while IFS= read -r -d '' file; do files+=("$file"); done < <(find "$outdir" -maxdepth 1 -type f -name '*.nc' -print0)
  if validate_daily_coverage "$year" "$mm" ${files[@]+"${files[@]}"}; then exit 0; else
    local status=$?
    [[ "$status" == 10 ]] || exit "$status"
  fi
  echo "[get] dataset=${dataset}"
  echo "      regex=${regex}"
  echo "      outdir=${outdir}"

  # Flat layout: put files directly in $outdir (no nested product/version dirs)
  "$CM" get \
    --dataset-id "$dataset" \
    --regex "$regex" \
    --output-directory "$outdir" \
    --no-directories

  check_flat_download_layout "$outdir"

  # A successful client exit does not prove a complete month.
  files=()
  while IFS= read -r -d '' file; do files+=("$file"); done < <(find "$outdir" -maxdepth 1 -type f -name '*.nc' -print0)
  validate_daily_coverage "$year" "$mm" ${files[@]+"${files[@]}"}

  # Manifest
  year=$(basename "$(dirname "$outdir")")
  mm=$(basename "$outdir")
  manifest="${outdir}/manifest_${year}${mm}.txt"
  DOWNLOAD_MANIFEST_TMP="$(mktemp "${manifest}.XXXXXX")"
  printf '%s\n' "${files[@]}" | sort > "$DOWNLOAD_MANIFEST_TMP"
  mv -f -- "$DOWNLOAD_MANIFEST_TMP" "$manifest"
  echo "[done] manifest: $manifest"
  exit 0
)

export -f validate_daily_coverage fetch_month check_flat_download_layout
export CM

# ========= Parallel execution =========
if [[ -s "$TASKS" ]]; then
  echo "============================"
  echo "[info] Starting downloads (parallel months = $CPUS)…"
  cat "$TASKS" | xargs -P "$CPUS" -n 1 -I {} bash -c '
    IFS="|" read -r dataset regex outdir <<< "{}"
    fetch_month "$dataset" "$regex" "$outdir"
  '
  echo "[info] All queued months processed."
else
  echo "[info] Nothing to download (tasks empty)."
fi

echo "[done] Check $OUTROOT"