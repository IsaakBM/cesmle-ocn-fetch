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
#    - Compute the existing whole-window climatology, 12 monthly climatology
#      fields, or four calendar-weighted seasonal climatology fields
#    - Preserve the same full-window mean logic used in the existing GLORYS
#      climatology workflow when the optional modes are not requested
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

# Shared scratch orchestration is also used by the time-series worker. Sourcing
# this file only defines the helper; it must never start the monthly-file job.
clim_shared_scratch() {
  python3 - "$1" "$2" <<'PY_SHARED_SCRATCH'
import datetime as dt
import glob
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile

import netCDF4 as nc
import numpy as np

worker, kind = sys.argv[1:]
env = dict(os.environ)
mode = env.get('CLIMATOLOGY_MODE', 'whole')
name = env.get('VAR', '')
root = Path(env.get('CLIM_SCRATCH_ROOT', ''))
if mode not in ('monthly', 'seasonal') or not name or not env.get('OUT_DIR'):
    raise SystemExit('ERROR: Shared scratch requires VAR, OUT_DIR and monthly or seasonal mode')
if not env.get('CLIM_SCRATCH_ROOT') or not root.is_absolute():
    raise SystemExit('ERROR: Shared scratch requires an absolute CLIM_SCRATCH_ROOT')
if env.get('CLIM_REUSE_MONTHS', '').strip():
    raise SystemExit('ERROR: Shared scratch does not consume legacy CLIM_REUSE_MONTHS fields')
reserve = env.get('CLIM_SCRATCH_HEADROOM_GB', '10')
if not reserve.isdigit():
    raise SystemExit('ERROR: CLIM_SCRATCH_HEADROOM_GB must be a nonnegative integer')
for executable in ('rsync', 'bash'):
    if not shutil.which(executable):
        raise SystemExit(f'ERROR: Installed {executable} is required; nothing installed automatically')

def years(value):
    return int(value[:4])

start = env.get('WINDOW_START', '200601' if kind == 'monthly' else '2006-01-01')
end = env.get('WINDOW_END', '201412' if kind == 'monthly' else '2014-12-31')
pattern = r'\d{6}' if kind == 'monthly' else r'\d{4}-\d{2}-\d{2}'
if not re.fullmatch(pattern, start) or not re.fullmatch(pattern, end):
    raise SystemExit('ERROR: Invalid shared-scratch window format')
if start[4:] != ('01' if kind == 'monthly' else '-01-01') or end[4:] != ('12' if kind == 'monthly' else '-12-31'):
    raise SystemExit('ERROR: Shared scratch requires complete January-December year windows')
first, last = years(start), years(end)
if not 1 < first <= last:
    raise SystemExit('ERROR: Invalid shared-scratch year range')
# Union of monthly and seasonal coverage: preceding December through final
# December. Both modes therefore reuse the same accepted source copies.
needed = {(year, month) for year in range(first, last + 1) for month in range(1, 13)}
needed.add((first - 1, 12))
if env.get('IN_FILE') and kind == 'timeseries':
    if env.get('IN_DIR'):
        raise SystemExit('ERROR: Provide IN_FILE or IN_DIR, not both')
    sources = [Path(env['IN_FILE']).resolve()]
else:
    if not env.get('IN_DIR'):
        raise SystemExit('ERROR: Missing IN_DIR')
    sources = sorted(Path(p).resolve() for p in glob.glob(str(Path(env['IN_DIR']) / env.get('FILE_GLOB', '*.nc'))) if Path(p).is_file())
if not sources:
    raise SystemExit('ERROR: No source files found')
merge = env.get('MERGE_INPUTS', 'auto')
if kind == 'timeseries' and merge not in ('auto', 'yes', 'no'):
    raise SystemExit('ERROR: Invalid MERGE_INPUTS')
if kind == 'timeseries' and merge == 'no':
    sources = sources[:1]
coverage = {}
selected = []
field_bytes = 0
for source in sources:
    with nc.Dataset(source) as ds:
        if name not in ds.variables or 'time' not in ds.variables:
            raise SystemExit(f'ERROR: Missing {name}/time: {source}')
        time = ds.variables['time']
        dates = nc.num2date(time[:], time.units, getattr(time, 'calendar', 'standard'))
        pairs = [(date.year, date.month) for date in dates]
        if kind == 'monthly':
            stamp = re.search(env.get('DATE_PATTERN', '[0-9]{6}'), source.name)
            if not stamp:
                continue
            text = stamp.group()
            expected_pair = (int(text[:4]), int(text[4:6]))
            if expected_pair not in needed:
                continue
            if pairs != [expected_pair]:
                raise SystemExit(f'ERROR: Filename/time mismatch or nonsingleton monthly input: {source}')
        contributing = [pair for pair in pairs if pair in needed]
        if not contributing:
            continue
        for pair in contributing:
            coverage[pair] = coverage.get(pair, 0) + 1
        var = ds.variables[name]
        if 'time' not in var.dimensions:
            raise SystemExit(f'ERROR: Scientific variable has no time dimension: {source}')
        spatial_size = int(np.prod([length for dim, length in zip(var.dimensions, var.shape) if dim != 'time']))
        field_bytes = max(field_bytes, spatial_size * max(8, var.dtype.itemsize))
        selected.append(source)
if set(coverage) != needed or any(count != 1 for count in coverage.values()):
    raise SystemExit('ERROR: Shared scratch needs exactly one input per month, including preceding December; source coverage failed before copying')
if len({p.name for p in selected}) != len(selected):
    raise SystemExit('ERROR: Source basenames collide')

out = Path(env['OUT_DIR']).resolve()
prefix = env.get('OUT_PREFIX') or f"{env.get('DATASET_LABEL', 'dataset')}_{name}"
canonical_tmp = Path(env.get('TMP_DIR') or out / 'tmp_clim').resolve()
out.mkdir(parents=True, exist_ok=True)
canonical_tmp.mkdir(parents=True, exist_ok=True)
# The same family lock used by the legacy monthly worker prevents competing
# publication. Seasonal locks are mode-specific; the cache lock serializes use.
family_lock = canonical_tmp / f'{prefix}_{mode}_{first:04d}01-{last:04d}12.lock'
root.mkdir(parents=True, exist_ok=True)
identity = json.dumps([kind, name, str(Path(env.get('IN_DIR') or selected[0]).resolve())])
key = hashlib.sha256(identity.encode()).hexdigest()[:20]
cache = root / f'clim_cache_{key}'
marker = cache / 'owner.json'
owner = {'version': 1, 'uid': os.getuid(), 'identity': identity}
if not cache.exists():
    cache.mkdir(mode=0o700)
    marker.write_text(json.dumps(owner))
if cache.is_symlink() or cache.stat().st_uid != os.getuid() or json.loads(marker.read_text()) != owner:
    raise SystemExit(f'ERROR: Unrecognized scratch cache; untouched: {cache}')
cache_lock = cache / '.lock'
held = []
work = None
publication = None
child = None

def stopped(signum, frame):
    if child is not None and child.poll() is None:
        os.killpg(child.pid, signal.SIGTERM)
        try:
            child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
    raise SystemExit(128 + signum)

for signum in (signal.SIGINT, signal.SIGTERM):
    signal.signal(signum, stopped)

def run(command, **kwargs):
    global child
    child = subprocess.Popen(command, start_new_session=True, **kwargs)
    status = child.wait()
    child = None
    if status:
        raise subprocess.CalledProcessError(status, command)

def signature(path):
    stat = path.stat()
    return {'path': str(path), 'bytes': stat.st_size, 'mtime_ns': stat.st_mtime_ns}

def record(path, value):
    temporary = path.with_name(path.name + '.new')
    temporary.write_text(json.dumps(value, sort_keys=True))
    os.replace(temporary, path)

def check_output(original, returned):
    if original.stat().st_size != returned.stat().st_size:
        raise ValueError('Returned file size mismatch')
    with nc.Dataset(original) as a, nc.Dataset(returned) as b:
        for dataset in (a, b):
            if dataset.variables[name].shape[dataset.variables[name].dimensions.index('time')] != 1:
                raise ValueError('Expected singleton output time')
            if dataset.climatology_product_type != mode or dataset.variables['time'].climatology != 'time_bnds':
                raise ValueError('Invalid output climatology metadata')
        if a.variables[name].shape != b.variables[name].shape or a.variables[name].dtype != b.variables[name].dtype:
            raise ValueError('Returned scientific variable layout mismatch')
        for coordinate in (*a.variables[name].dimensions, 'time_bnds'):
            np.testing.assert_array_equal(a.variables[coordinate][:], b.variables[coordinate][:])
        if set(a.ncattrs()) != set(b.ncattrs()):
            raise ValueError('Returned global metadata mismatch')
        for attr in a.ncattrs():
            np.testing.assert_array_equal(a.getncattr(attr), b.getncattr(attr))
        for coordinate in ('time', 'time_bnds'):
            for attr in ('units', 'calendar'):
                if getattr(a.variables[coordinate], attr) != getattr(b.variables[coordinate], attr):
                    raise ValueError('Returned time encoding mismatch')

try:
    for lock in (family_lock, cache_lock):
        try:
            lock.mkdir()
        except FileExistsError:
            raise SystemExit(f'ERROR: Outputs/cache locked; confirm previous writer stopped before removing stale lock: {lock}')
        held.append(lock)
    print(f'[SHARED CACHE] {cache}', flush=True)
    inputs = cache / 'inputs'
    inputs.mkdir(exist_ok=True)
    manifest_path = cache / 'sources.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    signatures = {source.name: signature(source) for source in selected}
    reusable = {source.name for source in selected if manifest.get(source.name, {}).get('source') == signatures[source.name]
                and (inputs / source.name).is_file()
                and manifest[source.name].get('staged') == signature(inputs / source.name)}
    missing_bytes = sum(source.stat().st_size for source in selected if source.name not in reusable)
    # All result/intermediate files live on scratch. Time-series seasonal mode
    # also materializes its selected window there. Count uncompressed fields.
    work_bytes = (last - first + 21) * field_bytes
    if kind == 'timeseries':
        work_bytes += len(needed) * field_bytes
    required = missing_bytes + work_bytes + int(reserve) * 1024**3
    available = shutil.disk_usage(cache).free
    print(f'[SPACE] new_inputs={missing_bytes} workspace={work_bytes} required={required} available={available}', flush=True)
    if available < required:
        raise SystemExit('ERROR: Insufficient shared scratch space; no inputs transferred')
    for source in selected:
        staged = inputs / source.name
        if source.name in reusable:
            print(f'[CACHE HIT] {source}', flush=True)
            continue
        # A stale provenance record must never bless an interrupted replacement.
        manifest.pop(source.name, None)
        record(manifest_path, manifest)
        print(f'[COPY IN] {dt.datetime.now(dt.timezone.utc).isoformat()} {source}', flush=True)
        run(['rsync', '-t', '--ignore-times', '--partial', '--partial-dir=.rsync-partial', '--no-whole-file',
             '--', str(source), str(staged)])
        if signature(source) != signatures[source.name] or staged.stat().st_size != source.stat().st_size:
            raise ValueError(f'Source changed or incomplete staged input: {source}')
        with nc.Dataset(staged) as ds:
            if name not in ds.variables or 'time' not in ds.variables:
                raise ValueError(f'Unreadable staged variable/time: {staged}')
        manifest[source.name] = {'source': signatures[source.name], 'staged': signature(staged)}
        record(manifest_path, manifest)
        print(f'[COPIED] {dt.datetime.now(dt.timezone.utc).isoformat()} {source}', flush=True)
    work = Path(tempfile.mkdtemp(prefix=f'work_{mode}_', dir=cache))
    # Cache may also contain chunks staged by other windows. Expose exactly this
    # window's contributing sources in a private view, without duplicating bytes.
    view = work / 'inputs'
    view.mkdir()
    for source in selected:
        (view / source.name).symlink_to(inputs / source.name)
    scratch_out = work / 'outputs'
    child_env = dict(env, CLIM_SCRATCH_POLICY='per_month', CLIM_SCRATCH_ROOT='',
                     CLIM_WORKERS='1', OUT_DIR=str(scratch_out), TMP_DIR=str(work / 'tmp'),
                     OUT_PREFIX=prefix, WINDOW_START=start, WINDOW_END=end)
    child_env.pop('IN_FILE', None)
    child_env['IN_DIR'] = str(view)
    child_env['FILE_GLOB'] = env.get('FILE_GLOB', '*.nc')
    run(['bash', worker], env=child_env)
    suffixes = [f'month_{m:02d}' for m in range(1, 13)] if mode == 'monthly' else [f'season_{s}' for s in ('DJF', 'MAM', 'JJA', 'SON')]
    names = [f'{prefix}_clim_{suffix}_{first}-{last}.nc' for suffix in suffixes]
    if any(signature(source) != signatures[source.name] for source in selected):
        raise ValueError('Source changed during calculation; canonical outputs retained')
    publication = Path(tempfile.mkdtemp(prefix=f'.{prefix}_{mode}.publish.', dir=out))
    for filename in names:
        original, returned = scratch_out / filename, publication / filename
        run(['rsync', '-t', '--', str(original), str(returned)])
        check_output(original, returned)
    # All candidates returned and checked before any accepted final is replaced.
    for filename in names:
        os.replace(publication / filename, out / filename)
        print(f'[PUBLISHED] {out / filename}', flush=True)
    print(f'[CACHE RETAINED] {cache} (inputs reusable by subsequent monthly/seasonal jobs)', flush=True)
finally:
    for private in (publication, work):
        if private is not None:
            shutil.rmtree(private)
    for lock in reversed(held):
        lock.rmdir()
PY_SHARED_SCRATCH
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi
if [[ "${CLIM_SCRATCH_POLICY:-per_month}" == shared ]]; then
  clim_shared_scratch "$0" monthly
  exit "$?"
elif [[ "${CLIM_SCRATCH_POLICY:-per_month}" != per_month ]]; then
  echo "ERROR: CLIM_SCRATCH_POLICY must be per_month or shared" >&2
  exit 1
fi

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
#   CLIMATOLOGY_MODE: whole | monthly | seasonal (default: whole)
#                     whole preserves the existing single-window product;
#                     monthly writes January-December climatologies; seasonal
#                     writes DJF, MAM, JJA, and SON climatologies and consumes
#                     the preceding December required by DJF
#   CLIM_WORKERS    : concurrent month/season tasks (default: allocated CPUs,
#                     capped at four); use 1 to benchmark serial storage access
#   CLIM_SCRATCH_ROOT: optional scratch parent for monthly input staging and
#                     calculation; defaults to no staging. Requires one worker.
#   CLIM_SCRATCH_POLICY: per_month (existing default) | shared. Shared retains a
#                     source cache across monthly/seasonal jobs; all calculation
#                     and intermediates run on scratch. See README for lifecycle.
#   CLIM_SCRATCH_HEADROOM_GB: free-space reserve after estimated working set (10)
#   CLIM_REUSE_MONTHS: explicit completed monthly temp fields to reuse, e.g. 01;
#                     only for known finished fields from the same settings
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
CLIM_SCRATCH_ROOT="${CLIM_SCRATCH_ROOT:-}"
CLIM_SCRATCH_HEADROOM_GB="${CLIM_SCRATCH_HEADROOM_GB:-10}"
CLIM_REUSE_MONTHS="${CLIM_REUSE_MONTHS:-}"
if [[ -n "$CLIM_SCRATCH_ROOT" ]]; then
  CLIM_WORKERS="${CLIM_WORKERS:-1}"
else
  CLIM_WORKERS="${CLIM_WORKERS:-${SLURM_CPUS_PER_TASK:-1}}"
fi
if ! [[ "$CLIM_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: CLIM_WORKERS must be a positive integer" >&2
  exit 1
fi
if (( CLIM_WORKERS > ${SLURM_CPUS_PER_TASK:-$CLIM_WORKERS} )); then
  echo "ERROR: CLIM_WORKERS exceeds allocated CPUs" >&2
  exit 1
fi
(( CLIM_WORKERS <= 4 )) || CLIM_WORKERS=4
if [[ -n "$CLIM_SCRATCH_ROOT" ]]; then
  if [[ "$CLIMATOLOGY_MODE" != monthly || "$CLIM_WORKERS" != 1 ]]; then
    echo "ERROR: Scratch staging currently requires monthly mode and CLIM_WORKERS=1" >&2
    exit 1
  fi
  if [[ "$CLIM_SCRATCH_ROOT" != /* || ! "$CLIM_SCRATCH_HEADROOM_GB" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Use an absolute scratch path and a nonnegative integer headroom" >&2
    exit 1
  fi
fi
if [[ -n "$CLIM_REUSE_MONTHS" && "$CLIMATOLOGY_MODE" != monthly ]]; then
  echo "ERROR: CLIM_REUSE_MONTHS requires monthly mode" >&2
  exit 1
fi
reuse_months=()
read -r -a reuse_months <<< "$CLIM_REUSE_MONTHS"
for reuse_month in "${reuse_months[@]-}"; do
  [[ -z "$reuse_month" ]] && continue
  if [[ ! "$reuse_month" =~ ^(0[1-9]|1[0-2])$ ]]; then
    echo "ERROR: CLIM_REUSE_MONTHS entries must be 01 through 12" >&2
    exit 1
  fi
done
# Each task uses a separate process/file; avoid hidden BLAS/OpenMP oversubscription.
if [[ "$CLIMATOLOGY_MODE" != "whole" ]]; then
  export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
  # Fail before any large reads if the in-place NetCDF finalizer is unavailable.
  python3 -c 'import netCDF4, numpy'
fi

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

if [[ "$CLIMATOLOGY_MODE" != "whole" && "$CLIMATOLOGY_MODE" != "monthly" && "$CLIMATOLOGY_MODE" != "seasonal" ]]; then
  echo "ERROR: CLIMATOLOGY_MODE must be one of: whole, monthly, seasonal"
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
echo "FIELD WORKERS: ${CLIM_WORKERS}"
echo "SCRATCH ROOT: ${CLIM_SCRATCH_ROOT:-<disabled>}"
echo "REUSE MONTHS: ${CLIM_REUSE_MONTHS:-<none>}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Gather files inside the target window
# ------------------------------------------------------------------------------
FILES=( "${IN_DIR}"/${FILE_GLOB} )

VALID_FILES=()
selection_start="${WINDOW_START}"
selection_end="${WINDOW_END}"
if [[ "$CLIMATOLOGY_MODE" == "seasonal" ]]; then
  selection_start="$((10#${WINDOW_START:0:4} - 1))12"
  selection_end="${WINDOW_END:0:4}11"
fi
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue

  bn="$(basename "$f")"
  yyyymm="$(printf "%s\n" "$bn" | grep -oE "${DATE_PATTERN}" | head -n 1 || true)"

  if [[ -z "${yyyymm}" ]]; then
    continue
  fi

  if [[ "${yyyymm}" < "${selection_start}" || "${yyyymm}" > "${selection_end}" ]]; then
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
python3 - "${selection_start}" "${selection_end}" monthly "${COVERAGE_INPUTS[@]}" <<'PY_MONTHLY_COVERAGE'
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
  local season_name="$8"
  local season_year_count="$9"
  local fill_top_missing="${10:-no}"

  # Monthly/seasonal outputs are already compressed by CDO. Update only tiny
  # time metadata and changed top-fill slabs in place in this private temp file.
  # The established whole-window path below retains its original encoding.
  if [[ -n "$product_type" ]]; then
    python3 - "$path" "$start_text" "$end_text" "$selected_count" "$product_type" "$month_number" "$role" "$season_name" "$season_year_count" "$fill_top_missing" "$VAR" <<'PY_FINALIZE'
import calendar
import datetime as dt
import sys

import netCDF4 as nc
import numpy as np

(path, start_text, end_text, count, kind, month, role, season, years,
 fill_top, var_hint) = sys.argv[1:]
if end_text.endswith("-last"):
    year, mon = map(int, end_text[:-5].split("-"))
    end_text = f"{year:04d}-{mon:02d}-{calendar.monthrange(year, mon)[1]:02d}"
start, end = map(dt.datetime.fromisoformat, (start_text, end_text))
# Match the existing whole-day midpoint policy exactly.
midpoint = start + dt.timedelta(days=(end - start).days // 2)
units = f"days since {start.year}-01-01 00:00:00"
cal = "proleptic_gregorian"
expected_month = int(month) if kind == "monthly" else {"DJF": 1, "MAM": 4, "JJA": 7, "SON": 10}[season]
if midpoint.month != expected_month:
    raise ValueError("Climatology midpoint is outside the expected month")
with nc.Dataset(path, "r+") as ds:
    if "time" not in ds.dimensions or len(ds.dimensions["time"]) != 1:
        raise ValueError("Expected singleton climatology time dimension")
    main = ds.variables[var_hint]
    zdim = next((d for d in main.dimensions if d.lower() in
                 ("depth", "depth_below_sea", "lev", "z_t")), None)
    filled_count = 0
    if fill_top == "yes" and zdim and main.ndim > 1:
        zaxis = main.dimensions.index(zdim)
        # Bound memory using 16 latitude rows, or one row of another spatial
        # dimension. Masked fill values, NaNs and infinities all remain missing.
        slab_dim = next((d for d in main.dimensions if d.lower() in ("lat", "latitude", "y")),
                        next(d for d in main.dimensions if d not in (zdim, "time")))
        slab_axis = main.dimensions.index(slab_dim)
        for offset in range(0, main.shape[slab_axis], 16):
            key = [slice(None)] * main.ndim
            key[slab_axis] = slice(offset, offset + 16)
            slab = np.ma.asarray(main[tuple(key)])
            values = np.moveaxis(np.asarray(slab.filled(np.nan)), zaxis, 0).copy()
            flat = values.reshape(values.shape[0], -1)
            valid = np.isfinite(flat)
            first = valid.argmax(axis=0)
            first[~valid.any(axis=0)] = -1
            columns = np.flatnonzero(first > 0)
            changed = False
            if columns.size:
                donors = flat[first[columns], columns].copy()
                for level in range(flat.shape[0]):
                    eligible = first[columns] > level
                    targets = columns[eligible]
                    if targets.size:
                        flat[level, targets] = donors[eligible]
                        filled_count += targets.size
                        changed = True
            if changed:
                # Preserve interior infinities exactly as the original rule did;
                # only missing cells above the first finite donor are changed.
                main[tuple(key)] = np.ma.masked_where(
                    np.isnan(np.moveaxis(values, 0, zaxis)),
                    np.moveaxis(values, 0, zaxis),
                )
    bounds_name = "time_bnds"
    if "bnds" not in ds.dimensions:
        ds.createDimension("bnds", 2)
    if len(ds.dimensions["bnds"]) != 2:
        raise ValueError("Expected two climatology bounds")
    if bounds_name not in ds.variables:
        ds.createVariable(bounds_name, "f8", ("time", "bnds"))
    bounds = ds.variables[bounds_name]
    if bounds.dimensions != ("time", "bnds"):
        raise ValueError("Incorrect time_bnds dimensions")
    time = ds.variables["time"]
    for variable in (time, bounds):
        variable.setncatts({"units": units, "calendar": cal})
    if "bounds" in time.ncattrs():
        time.delncattr("bounds")
    time.setncatts({"long_name": "climatology time", "climatology": bounds_name})
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
# Reopen the serialized time fields, without reading the scientific array.
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
print(f"[FINALIZED] {kind} {month or season}: top cells filled={filled_count}", flush=True)
PY_FINALIZE
    return
  fi

  python3 - "$path" "$start_text" "$end_text" "$selected_count" "$product_type" "$month_number" "$role" "$season_name" "$season_year_count" "$fill_top_missing" "$VAR" <<'PY_METADATA'
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

# Independent fields have distinct temp names. Wait for all tasks in a batch
# before publishing; any failed task aborts the entire product family.
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

if [[ "$CLIMATOLOGY_MODE" == "monthly" ]]; then
  start_year="${WINDOW_START:0:4}"
  end_year="${WINDOW_END:0:4}"
  expected_per_field=$((10#${end_year} - 10#${start_year} + 1))
  monthly_temps=()
  monthly_outputs=()

  # One writer per variable/window, including during staging and final publication.
  monthly_lock="${TMP_DIR}/${OUT_PREFIX}_monthly_${WINDOW_START}-${WINDOW_END}.lock"
  if ! mkdir "$monthly_lock" 2>/dev/null; then
    echo "ERROR: Monthly outputs locked: $monthly_lock; confirm the previous job stopped before removing a stale lock" >&2
    exit 1
  fi
  scratch_job_dir=""
  cleanup_monthly_job() {
    local pid
    for pid in "${field_pids[@]-}"; do
      [[ -n "$pid" ]] || continue
      kill -TERM "$pid" 2>/dev/null || true
    done
    for pid in "${field_pids[@]-}"; do
      [[ -n "$pid" ]] || continue
      wait "$pid" 2>/dev/null || true
    done
    [[ -z "$scratch_job_dir" ]] || rm -rf -- "$scratch_job_dir"
    rmdir -- "$monthly_lock"
  }
  trap cleanup_monthly_job EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ -n "$CLIM_SCRATCH_ROOT" ]]; then
    mkdir -p "$CLIM_SCRATCH_ROOT"
    scratch_job_dir="$(mktemp -d "${CLIM_SCRATCH_ROOT%/}/clim_${VAR}_${SLURM_JOB_ID:-local}.XXXXXX")"
    echo "[SCRATCH] $scratch_job_dir"
  fi

  echo "[STEP1] Computing twelve calendar-month climatologies"
  process_month() (
    set -euo pipefail
    field_scratch=""
    publish_dir=""
    cleanup_month() {
      [[ -z "$publish_dir" ]] || rm -rf -- "$publish_dir"
      [[ -z "$field_scratch" ]] || rm -rf -- "$field_scratch"
    }
    trap cleanup_month EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    month="$1"
    echo "[START] month=${month} $(date -u +%FT%TZ)"
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
    monthly_out="${OUT_DIR}/${OUT_PREFIX}_clim_month_${month_padded}_${start_year}-${end_year}.nc"
    if [[ " ${CLIM_REUSE_MONTHS} " == *" ${month_padded} "* ]]; then
      python3 - "$monthly_tmp" "$VAR" "$month" "$start_year" "$end_year" "${month_files[@]}" <<'PY_REUSE_MONTH'
import calendar
import datetime as dt
import os
import sys
import netCDF4 as nc
import numpy as np

path, name, month, start, end, *sources = sys.argv[1:]
month, start, end = map(int, (month, start, end))
with nc.Dataset(path) as ds, nc.Dataset(sources[0]) as source:
    assert ds.climatology_product_type == 'monthly'
    assert int(ds.climatology_month) == month
    assert int(ds.climatology_selected_timesteps) == len(sources)
    expected_start = dt.datetime(start, month, 1)
    expected_end = dt.datetime(end, month, calendar.monthrange(end, month)[1])
    assert ds.climatology_window_start == expected_start.date().isoformat()
    assert ds.climatology_window_end == expected_end.date().isoformat()
    assert ds.variables[name].shape == source.variables[name].shape
    assert ds.variables[name].units == source.variables[name].units
    for dimension in ds.variables[name].dimensions:
        if dimension != 'time':
            np.testing.assert_array_equal(ds.variables[dimension][:], source.variables[dimension][:])
    time, bounds = ds.variables['time'], ds.variables['time_bnds']
    assert len(time) == 1 and time.climatology == 'time_bnds'
    assert time.units == bounds.units and time.calendar == bounds.calendar
    np.testing.assert_array_equal(bounds[:], nc.date2num([[expected_start, expected_end]], time.units, time.calendar))
    assert bounds[0, 0] <= time[0] <= bounds[0, 1]
assert all(os.stat(source).st_mtime_ns <= os.stat(path).st_mtime_ns for source in sources), 'Input newer than requested completed field'
PY_REUSE_MONTH
      echo "[REUSE] month=${month_padded} previously finalized field: $monthly_tmp"
      exit 0
    fi

    calculation_tmp="$monthly_tmp"
    calculation_files=( "${month_files[@]}" )
    if [[ -n "$scratch_job_dir" ]]; then
      python3 - "$scratch_job_dir" "$VAR" "$CLIM_SCRATCH_HEADROOM_GB" "${month_files[@]}" <<'PY_SCRATCH_SPACE'
import os
import shutil
import sys
import netCDF4 as nc

root, name, reserve, *sources = sys.argv[1:]
source_bytes = sum(os.stat(path).st_size for path in sources)
with nc.Dataset(sources[0]) as ds:
    variable = ds.variables[name]
    output_bytes = variable.size * variable.dtype.itemsize
required = source_bytes + 2 * output_bytes + int(reserve) * 1024**3
available = shutil.disk_usage(root).free
print(f'[SPACE] inputs={source_bytes} estimated_required={required} available={available}', flush=True)
if available < required:
    raise SystemExit('ERROR: Insufficient scratch space; no inputs staged')
PY_SCRATCH_SPACE
      field_scratch="$(mktemp -d "${scratch_job_dir}/month_${month_padded}.XXXXXX")"
      calculation_files=()
      for input_file in "${month_files[@]}"; do
        staged_file="${field_scratch}/$(basename "$input_file")"
        echo "[COPY IN] $(date -u +%FT%TZ) $input_file"
        cp -- "$input_file" "$staged_file"
        python3 - "$input_file" "$staged_file" <<'PY_COPY_SIZE'
import os
import sys
assert os.stat(sys.argv[1]).st_size == os.stat(sys.argv[2]).st_size, 'Incomplete staged copy'
PY_COPY_SIZE
        calculation_files+=( "$staged_file" )
        echo "[COPIED] $(date -u +%FT%TZ) $input_file"
      done
      calculation_tmp="${field_scratch}/$(basename "$monthly_tmp")"
    else
      rm -f "$monthly_tmp"
    fi
    echo "[CALCULATE] month=${month_padded} $(date -u +%FT%TZ)"
    if [[ -n "$field_scratch" ]]; then
      cdo -L -O -P 1 -f nc4c -k auto -z zip_1 timmean -mergetime "${calculation_files[@]}" "$calculation_tmp"
    else
      cdo -L -O -P 1 -f nc4c -z zip_1 timmean -mergetime "${calculation_files[@]}" "$calculation_tmp"
    fi
    write_climatology_metadata "$calculation_tmp" \
      "${start_year}-${month_padded}-01" "${end_year}-${month_padded}-last" \
      "${#month_files[@]}" "monthly" "$month" "calendar_month" "" "" \
      "$FILL_TOP_MISSING"
    if [[ -n "$field_scratch" ]]; then
      publish_dir="$(mktemp -d "${TMP_DIR}/.${OUT_PREFIX}_month_${month_padded}.publish.XXXXXX")"
      echo "[COPY OUT] month=${month_padded} $(date -u +%FT%TZ)"
      cp -- "$calculation_tmp" "$publish_dir/output.nc"
      python3 - "$calculation_tmp" "$publish_dir/output.nc" "$VAR" <<'PY_RETURNED_FIELD'
import os
import sys
import netCDF4 as nc
import numpy as np

original, returned, name = sys.argv[1:]
assert os.stat(original).st_size == os.stat(returned).st_size, 'Incomplete returned copy'
with nc.Dataset(original) as before, nc.Dataset(returned) as after:
    assert before.variables[name].shape == after.variables[name].shape
    assert before.variables[name].dtype == after.variables[name].dtype
    for coordinate in before.variables[name].dimensions:
        np.testing.assert_array_equal(before.variables[coordinate][:], after.variables[coordinate][:])
    np.testing.assert_array_equal(before.variables['time_bnds'][:], after.variables['time_bnds'][:])
    for attribute in ('units', 'calendar', 'climatology'):
        assert getattr(before.variables['time'], attribute) == getattr(after.variables['time'], attribute)
PY_RETURNED_FIELD
      mv -f -- "$publish_dir/output.nc" "$monthly_tmp"
      echo "[RETURNED] month=${month_padded} $(date -u +%FT%TZ)"
    fi
    echo "[READY] month=${month_padded} $(date -u +%FT%TZ)"
  )
  for month in {1..12}; do
    month_padded="$(printf '%02d' "$month")"
    monthly_temps+=( "${TMP_DIR}/${OUT_PREFIX}_clim_month_${month_padded}_${start_year}-${end_year}.tmp.nc" )
    monthly_outputs+=( "${OUT_DIR}/${OUT_PREFIX}_clim_month_${month_padded}_${start_year}-${end_year}.nc" )
    process_month "$month" &
    field_pids+=( "$!" )
    if (( ${#field_pids[@]} >= CLIM_WORKERS )); then wait_fields; fi
  done
  wait_fields

  echo "[STEP2] Publishing all 12 monthly climatology fields"
  for index in "${!monthly_temps[@]}"; do
    mv -f "${monthly_temps[$index]}" "${monthly_outputs[$index]}"
    echo "[DONE ] ${monthly_outputs[$index]}"
  done

  echo
  echo "All 12 monthly climatology fields completed for VAR=${VAR}"
  exit 0
fi

if [[ "$CLIMATOLOGY_MODE" == "seasonal" ]]; then
  start_year="${WINDOW_START:0:4}"
  end_year="${WINDOW_END:0:4}"
  expected_season_years=$((10#${end_year} - 10#${start_year} + 1))
  seasonal_temps=()
  seasonal_outputs=()

  echo "[STEP1] Computing calendar-weighted season-year means"
  process_season() (
    set -euo pipefail
    season="$1"
    echo "[START] season=${season} $(date -u +%FT%TZ)"
    season_year_means=()
    for ((year=10#${start_year}; year<=10#${end_year}; year++)); do
      case "$season" in
        DJF)
          required_months=( "$((year - 1))12" "${year}01" "${year}02" )
          ;;
        MAM)
          required_months=( "${year}03" "${year}04" "${year}05" )
          ;;
        JJA)
          required_months=( "${year}06" "${year}07" "${year}08" )
          ;;
        SON)
          required_months=( "${year}09" "${year}10" "${year}11" )
          ;;
      esac

      season_files=()
      for required_month in "${required_months[@]}"; do
        matched_file=""
        for input_file in "${VALID_FILES[@]}"; do
          filename="$(basename "$input_file")"
          yyyymm="$(printf '%s\n' "$filename" | grep -oE "${DATE_PATTERN}" | head -n 1 || true)"
          if [[ "$yyyymm" == "$required_month" ]]; then
            matched_file="$input_file"
            break
          fi
        done
        if [[ -z "$matched_file" ]]; then
          echo "ERROR: ${season} ${year} missing source month ${required_month}" >&2
          exit 1
        fi
        season_files+=( "$matched_file" )
      done
      if [[ "${#season_files[@]}" -ne 3 ]]; then
        echo "ERROR: ${season} ${year} expected 3 monthly files, found ${#season_files[@]}" >&2
        exit 1
      fi

      season_input="${TMP_DIR}/${OUT_PREFIX}_${season}_${year}.selected.tmp.nc"
      season_year_mean="${TMP_DIR}/${OUT_PREFIX}_${season}_${year}.weighted.tmp.nc"
      rm -f "$season_input" "$season_year_mean"
      # Stream the three inputs into the weighted mean instead of materializing
      # a three-field seasonal input on shared storage.
      cdo -L -O -P 1 -f nc4c -z zip_1 yearmonmean -setyear,"${year}" -mergetime "${season_files[@]}" "$season_year_mean"
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
      "$expected_season_years" "$FILL_TOP_MISSING"
    rm -f "${season_year_means[@]}" "$season_input"
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

  echo "[STEP2] Publishing all four seasonal climatology fields"
  for index in "${!seasonal_temps[@]}"; do
    mv -f "${seasonal_temps[$index]}" "${seasonal_outputs[$index]}"
    echo "[DONE ] ${seasonal_outputs[$index]}"
  done
  rm -f "${TMP_DIR}"/*.selected.tmp.nc
  echo
  echo "All four seasonal climatology fields completed for VAR=${VAR}"
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
  "${#VALID_FILES[@]}" "" "" "" "" ""

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
