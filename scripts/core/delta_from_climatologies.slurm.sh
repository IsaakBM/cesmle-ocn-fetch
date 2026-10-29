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
#   DELTA_MODE        : additive | log_ratio (default: additive)
#   LOG_RATIO_FLOOR   : optional positive floor for log_ratio inputs
#                       (default: 0)
#   LOG_RATIO_INVALID_POLICY
#                     : missing | no_change for invalid/floored log_ratio cells
#                       (default: missing)
#   LOG_RATIO_MIN_FACTOR
#                     : optional inclusive lower bound for exp(log_ratio)
#                       (default: 0, no lower-factor rejection)
#   LOG_RATIO_MAX_FACTOR
#                     : optional inclusive upper bound for exp(log_ratio)
#                       (default: inf, no upper-factor rejection)
#   REGRID_DELTA      : yes | no (default: no)
#   GRIDFILE          : target grid file when REGRID_DELTA=yes
#   METHOD            : CDO remapping method (default: remapbil)
#   REGRID_OUT_DIR    : output dir for regridded deltas
#                       (default: <OUT_DIR>/regridded)
#   REGRID_SUFFIX     : suffix for regridded deltas
#                       (default: <gridfile basename>)
#   CLIMATOLOGY_MODE  : whole | monthly (default: whole); monthly input paths
#                       must contain {month}, expanded to 01..12
#   DELTA_SCRATCH_ROOT: private workspaces under this root; required for monthly
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
DELTA_MODE="${DELTA_MODE:-additive}"
LOG_RATIO_FLOOR="${LOG_RATIO_FLOOR:-0}"
LOG_RATIO_INVALID_POLICY="${LOG_RATIO_INVALID_POLICY:-missing}"
LOG_RATIO_MIN_FACTOR="${LOG_RATIO_MIN_FACTOR:-0}"
LOG_RATIO_MAX_FACTOR="${LOG_RATIO_MAX_FACTOR:-inf}"
REGRID_DELTA="${REGRID_DELTA:-no}"
GRIDFILE="${GRIDFILE:-}"
METHOD="${METHOD:-remapbil}"
REGRID_OUT_DIR="${REGRID_OUT_DIR:-}"
REGRID_SUFFIX="${REGRID_SUFFIX:-}"
# Monthly mode accepts exact input templates containing {month} (01..12).
# One Slurm job processes twelve pairs sequentially; whole remains compatible.
CLIMATOLOGY_MODE="${CLIMATOLOGY_MODE:-whole}"
DELTA_SCRATCH_ROOT="${DELTA_SCRATCH_ROOT:-}"
DELTA_MONTH="${DELTA_MONTH:-}"
if [[ "$CLIMATOLOGY_MODE" != whole && "$CLIMATOLOGY_MODE" != monthly ]]; then
  echo "ERROR: Delta CLIMATOLOGY_MODE must be whole or monthly" >&2
  exit 1
fi

if [[ -z "$VAR" || -z "$BASELINE_FILE" || -z "$FUTURE_FILE" || -z "$OUT_DIR" ]]; then
  echo "ERROR: Missing required environment variables."
  echo "Required: VAR, BASELINE_FILE, FUTURE_FILE, OUT_DIR"
  echo "Optional: DATASET_LABEL, TMP_DIR, FUTURE_TAG, BASELINE_TAG, OUT_PREFIX, DELTA_MODE, REGRID_DELTA, GRIDFILE, METHOD, REGRID_OUT_DIR, REGRID_SUFFIX"
  exit 1
fi

if [[ "$CLIMATOLOGY_MODE" != monthly && ! -f "$BASELINE_FILE" ]]; then
  echo "ERROR: Baseline file not found: ${BASELINE_FILE}"
  exit 1
fi

if [[ "$CLIMATOLOGY_MODE" != monthly && ! -f "$FUTURE_FILE" ]]; then
  echo "ERROR: Future file not found: ${FUTURE_FILE}"
  exit 1
fi

if [[ "$REGRID_DELTA" != "yes" && "$REGRID_DELTA" != "no" ]]; then
  echo "ERROR: REGRID_DELTA must be one of: yes, no"
  exit 1
fi

if [[ "$DELTA_MODE" != "additive" && "$DELTA_MODE" != "log_ratio" ]]; then
  echo "ERROR: DELTA_MODE must be one of: additive, log_ratio"
  exit 1
fi

if [[ "$LOG_RATIO_INVALID_POLICY" != "missing" && "$LOG_RATIO_INVALID_POLICY" != "no_change" ]]; then
  echo "ERROR: LOG_RATIO_INVALID_POLICY must be one of: missing, no_change"
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

if [[ "$CLIMATOLOGY_MODE" == monthly || -n "$DELTA_SCRATCH_ROOT" ]]; then
  # Keep orchestration here rather than introducing a second scientific worker.
  # Re-enter this same file (including Slurm's spooled copy) for each pair.
  export VAR BASELINE_FILE FUTURE_FILE OUT_DIR TMP_DIR OUT_PREFIX FUTURE_TAG BASELINE_TAG
  export CLIMATOLOGY_MODE DELTA_SCRATCH_ROOT REGRID_DELTA REGRID_OUT_DIR GRIDFILE
  export DELTA_MODE LOG_RATIO_FLOOR LOG_RATIO_INVALID_POLICY LOG_RATIO_MIN_FACTOR LOG_RATIO_MAX_FACTOR
  export METHOD REGRID_SUFFIX DATASET_LABEL
  python3 - "$0" <<'PY_DELTA_BATCH'
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

import netCDF4 as nc

env = os.environ.copy()
monthly = env['CLIMATOLOGY_MODE'] == 'monthly'
scratch = env['DELTA_SCRATCH_ROOT']
if monthly and not scratch:
    raise SystemExit('ERROR: Monthly deltas require DELTA_SCRATCH_ROOT')
root = Path(scratch).resolve()
root.mkdir(parents=True, exist_ok=True)
pairs = []
for month in range(1, 13) if monthly else (0,):
    token = f'{month:02d}'
    if monthly and any('{month}' not in env[key] for key in ('BASELINE_FILE', 'FUTURE_FILE')):
        raise SystemExit('ERROR: Monthly input templates must contain {month}')
    paths = [Path(env[key].replace('{month}', token)).resolve()
             for key in ('BASELINE_FILE', 'FUTURE_FILE')]
    for path, tag in zip(paths, (env['BASELINE_TAG'], env['FUTURE_TAG'])):
        if not path.is_file():
            raise SystemExit(f'ERROR: Missing delta input: {path}')
        with nc.Dataset(path) as ds:
            if env['VAR'] not in ds.variables:
                raise SystemExit(f'ERROR: Missing variable in {path}')
            if monthly:
                import calendar
                import datetime as dt
                import numpy as np
                a, b = map(int, tag.split('-'))
                if (getattr(ds, 'climatology_product_type', '') != 'monthly'
                        or int(getattr(ds, 'climatology_month', 0)) != month
                        or int(getattr(ds, 'climatology_selected_timesteps', 0)) != b - a + 1):
                    raise SystemExit(f'ERROR: Monthly product/month/count mismatch: {path}')
                start = dt.datetime(a, month, 1)
                end = dt.datetime(b, month, calendar.monthrange(b, month)[1])
                if (ds.climatology_window_start != start.date().isoformat()
                        or ds.climatology_window_end != end.date().isoformat()):
                    raise SystemExit(f'ERROR: Monthly window mismatch: {path}')
                time, bounds = ds.variables['time'], ds.variables['time_bnds']
                if (time.shape != (1,) or bounds.shape != (1, 2)
                        or time.climatology != 'time_bnds' or time.units != bounds.units
                        or time.calendar != bounds.calendar or time.calendar != 'proleptic_gregorian'):
                    raise SystemExit(f'ERROR: Invalid monthly time encoding: {path}')
                np.testing.assert_allclose(bounds[:], nc.date2num([[start, end]], time.units, time.calendar),
                                           rtol=0, atol=1e-8)
                midpoint = start + dt.timedelta(days=(end - start).days // 2)
                np.testing.assert_allclose(time[:], nc.date2num([midpoint], time.units, time.calendar),
                                           rtol=0, atol=1e-8)
    signatures = [(p.stat().st_size, p.stat().st_mtime_ns) for p in paths]
    pairs.append((token if monthly else '', paths, signatures))

out = Path(env['OUT_DIR']).resolve()
out.mkdir(parents=True, exist_ok=True)
stem = f"{env['OUT_PREFIX']}_delta_{env['FUTURE_TAG']}_minus_{env['BASELINE_TAG']}"
lock = out / f'.{stem}.lock'
try:
    lock.mkdir()
except FileExistsError:
    raise SystemExit(f'ERROR: Delta outputs locked: {lock}; confirm the previous job stopped before removing a stale lock')
child = None
def run(command, **kwargs):
    global child
    child = subprocess.Popen(command, start_new_session=True, **kwargs)
    status = child.wait()
    child = None
    if status:
        raise subprocess.CalledProcessError(status, command)

def stop(signum, frame):
    if child is not None and child.poll() is None:
        os.killpg(child.pid, signal.SIGTERM)
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    for month, paths, signatures in pairs:
        if signatures != [(p.stat().st_size, p.stat().st_mtime_ns) for p in paths]:
            raise SystemExit('ERROR: Delta sources changed after preflight')
        # Include the high-resolution target and QC/remapping intermediates in
        # a conservative per-pair space estimate. Never hold twelve HD fields.
        with nc.Dataset(paths[1]) as ds:
            field = ds.variables[env['VAR']]
            cells = field.size
            levels = 1
            for dimension in field.dimensions:
                if dimension not in ('time', 'lat', 'lon', 'latitude', 'longitude', 'x', 'y'):
                    levels *= len(ds.dimensions[dimension])
        if env['REGRID_DELTA'] == 'yes':
            grid = {}
            for line in Path(env['GRIDFILE']).read_text().splitlines():
                key, sep, value = line.partition('=')
                if sep and key.strip() in ('gridsize', 'xsize', 'ysize'):
                    grid[key.strip()] = int(value.strip())
            target_cells = grid.get('gridsize', grid.get('xsize', 0) * grid.get('ysize', 0))
            if not target_cells:
                raise SystemExit('ERROR: Cannot estimate target grid size for scratch')
            cells = max(cells, target_cells * levels)
        required = sum(p.stat().st_size for p in paths) + cells * 8 * 8 + 10 * 1024**3
        available = shutil.disk_usage(root).free
        print(f'[SPACE] required={required} available={available}', flush=True)
        if available < required:
            raise SystemExit('ERROR: Insufficient delta scratch space')
        with tempfile.TemporaryDirectory(prefix='delta_', dir=root) as work_text:
            work = Path(work_text)
            job_env = dict(env, CLIMATOLOGY_MODE='whole', DELTA_SCRATCH_ROOT='',
                           DELTA_MONTH=month, OUT_DIR=str(work/'native'),
                           REGRID_OUT_DIR=str(work/'regrid'), TMP_DIR=str(work/'tmp'),
                           OUT_PREFIX=env['OUT_PREFIX'] + (f'_month_{month}' if month else ''))
            for role, path in zip(('BASELINE', 'FUTURE'), paths):
                destination = work / f'{role.lower()}.nc'
                print(f'[COPY IN] {path}', flush=True)
                run(['rsync', '-t', '--', str(path), str(destination)])
                job_env[f'{role}_FILE'] = str(destination)
                job_env[f'DELTA_{role}_SOURCE'] = str(path)
            if env['REGRID_DELTA'] == 'yes':
                shutil.copyfile(env['GRIDFILE'], work/'grid.txt')
                job_env['GRIDFILE'] = str(work/'grid.txt')
            print(f'[CALCULATE] month={month or "whole"}', flush=True)
            run(['bash', sys.argv[1]], env=job_env)
            if signatures != [(p.stat().st_size, p.stat().st_mtime_ns) for p in paths]:
                raise SystemExit('ERROR: Delta sources changed during calculation')
            destinations = [(work/'native', out)]
            if env['REGRID_DELTA'] == 'yes':
                destinations.append((work/'regrid', Path(env['REGRID_OUT_DIR']).resolve()))
            for source_dir, destination_dir in destinations:
                products = list(source_dir.glob('*.nc'))
                if len(products) != 1:
                    raise SystemExit(f'ERROR: Expected exactly one delta in {source_dir}')
                product = products[0]
                destination_dir.mkdir(parents=True, exist_ok=True)
                with tempfile.TemporaryDirectory(prefix='.delta_publish_', dir=destination_dir) as publish:
                    staged = Path(publish)/product.name
                    run(['rsync', '-t', '--', str(product), str(staged)])
                    if staged.stat().st_size != product.stat().st_size:
                        raise SystemExit('ERROR: Delta copy-back size mismatch')
                    with nc.Dataset(staged) as ds, nc.Dataset(product) as original:
                        if ds.variables[env['VAR']].shape != original.variables[env['VAR']].shape:
                            raise SystemExit('ERROR: Delta copy-back shape mismatch')
                    os.replace(staged, destination_dir/product.name)
                print(f'[PUBLISHED] {destination_dir/product.name}', flush=True)
finally:
    lock.rmdir()
print(f'All {len(pairs)} delta pairs completed for VAR={env["VAR"]}', flush=True)
PY_DELTA_BATCH
  exit "$?"
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
echo "DELTA MODE      : ${DELTA_MODE}"
if [[ "$DELTA_MODE" == "log_ratio" ]]; then
  echo "LOG RATIO FLOOR : ${LOG_RATIO_FLOOR}"
  echo "LOG RATIO POLICY: ${LOG_RATIO_INVALID_POLICY}"
  echo "LOG RATIO FACTOR: ${LOG_RATIO_MIN_FACTOR} to ${LOG_RATIO_MAX_FACTOR}"
fi
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

# ------------------------------------------------------------------------------
# Validate spatial identity for both additive and log-ratio calculations.
# Historical/future climatology dates intentionally differ; spatial positions must
# match exactly. Validate before replacing any accepted delta output.
# ------------------------------------------------------------------------------
python3 - "${BASELINE_FILE}" "${FUTURE_FILE}" "${VAR}" <<'PY_SPATIAL_CHECK'
import sys
import numpy as np
import xarray as xr

def validate_spatial_coordinates(reference, candidate, label, allow_broadcast=False):
    """Check locations before positional arithmetic; climatology time may differ."""
    ref_dims = set(reference.dims) - {"time"}
    other_dims = set(candidate.dims) - {"time"}
    if other_dims - ref_dims or (not allow_broadcast and ref_dims != other_dims):
        raise ValueError(f"{label}: spatial dimensions differ: {reference.dims} vs {candidate.dims}")
    for dim in other_dims:
        if reference.sizes[dim] != candidate.sizes[dim]:
            raise ValueError(f"{label}: size mismatch for {dim}")
        if dim not in reference.coords or dim not in candidate.coords:
            raise ValueError(f"{label}: missing coordinate for spatial dimension {dim}")
    # Compare dimension coordinates and auxiliary latitude/longitude coordinates.
    # Restrict a broadcast mask to the dimensions it actually supplies.
    names = {name for array in (reference, candidate) for name, coord in array.coords.items()
             if coord.dims and "time" not in coord.dims and set(coord.dims) <= other_dims}
    for name in sorted(names):
        if name not in reference.coords or name not in candidate.coords:
            raise ValueError(f"{label}: spatial coordinate {name} is missing in one input")
        left, right = reference.coords[name], candidate.coords[name]
        if set(left.dims) != set(right.dims):
            raise ValueError(f"{label}: coordinate dimensions differ for {name}")
        right = right.transpose(*left.dims)
        if not np.array_equal(left.values, right.values):
            raise ValueError(f"{label}: coordinate values/order differ for {name}; verify the prepared grids")
        for attribute in ("units", "positive"):
            if left.attrs.get(attribute, "") != right.attrs.get(attribute, ""):
                raise ValueError(f"{label}: {attribute} differs for {name}; no automatic conversion is performed")
    for array in (reference, candidate):
        if "time" in array.dims and array.sizes["time"] != 1:
            raise ValueError(f"{label}: expected singleton climatology time")

with xr.open_dataset(sys.argv[1]) as baseline, xr.open_dataset(sys.argv[2]) as future:
    variable = sys.argv[3]
    if variable not in baseline or variable not in future:
        raise SystemExit(f"ERROR: Requested variable {variable} missing from a delta input")
    validate_spatial_coordinates(baseline[variable], future[variable], "baseline/future")
    if baseline[variable].attrs.get('units', '') != future[variable].attrs.get('units', ''):
        raise SystemExit('ERROR: Baseline/future scientific units differ; no automatic conversion is performed')
print("SPATIAL CHECK: PASS (baseline/future)")
PY_SPATIAL_CHECK

# CDO arithmetic/remapping may drop climatology linkage or bounds. Restore the
# future product's exact serialized time record after each scientific operation.
finalize_delta() {
  python3 - "$1" "$FUTURE_FILE" "$VAR" "$DELTA_MODE" \
    "${DELTA_BASELINE_SOURCE:-$BASELINE_FILE}" "${DELTA_FUTURE_SOURCE:-$FUTURE_FILE}" \
    "$BASELINE_TAG" "$FUTURE_TAG" "$DELTA_MONTH" <<'PY_DELTA_METADATA'
import sys
import netCDF4 as nc
import numpy as np

path, future, variable, mode, baseline_source, future_source, base_tag, future_tag, month = sys.argv[1:]
with nc.Dataset(future) as source, nc.Dataset(path, 'r+') as out:
    if variable not in out.variables:
        raise ValueError(f'Missing scientific delta variable: {variable}')
    for name in source.ncattrs():
        if name.startswith('climatology_'):
            out.setncattr(name, source.getncattr(name))
    out.setncatts(dict(delta_mode=mode, delta_baseline_file=baseline_source,
                      delta_future_file=future_source, delta_baseline_window=base_tag,
                      delta_future_window=future_tag))
    out.variables[variable].setncattr('delta_mode', mode)
    if 'time' in source.variables and 'climatology' in source.variables['time'].ncattrs():
        time = source.variables['time']
        bound_name = time.climatology
        for name in ('time', bound_name):
            src = source.variables[name]
            for dim in src.dimensions:
                if dim not in out.dimensions:
                    out.createDimension(dim, len(source.dimensions[dim]))
            if name not in out.variables:
                out.createVariable(name, src.dtype, src.dimensions)
            dest = out.variables[name]
            if dest.dimensions != src.dimensions or dest.shape != src.shape:
                raise ValueError(f'Incorrect delta time/bounds dimensions: {name}')
            # CDO's ordinary time:bounds must not conflict with time:climatology.
            if name == 'time' and 'bounds' in dest.ncattrs():
                dest.delncattr('bounds')
            dest.setncatts({attr: src.getncattr(attr) for attr in src.ncattrs() if attr != '_FillValue'})
            dest[:] = src[:]
        if month:
            decoded = nc.num2date(out.variables['time'][:], time.units, time.calendar)[0]
            if decoded.month != int(month):
                raise ValueError('Delta time differs from requested calendar month')
        np.testing.assert_array_equal(out.variables[bound_name][:], source.variables[bound_name][:])
    elif month:
        raise ValueError('Monthly delta is missing future climatology time encoding')
PY_DELTA_METADATA
}

echo "[STEP1] Clearing temporary delta; retaining existing output until replacement succeeds"
rm -f "${TMP_DELTA}"

echo "[STEP2] Computing delta with mode: ${DELTA_MODE}"
# Monthly high-resolution fields can exceed classic NetCDF size limits. Keep
# them compressed in NetCDF4, as in the existing climatology workers.
CDO_OUTPUT_ARGS=()
if [[ -n "$DELTA_MONTH" ]]; then
  CDO_OUTPUT_ARGS=(-f nc4c -z zip_1)
fi
if [[ "$DELTA_MODE" == "additive" ]]; then
  cdo -L -O ${CDO_OUTPUT_ARGS[@]+"${CDO_OUTPUT_ARGS[@]}"} sub "${FUTURE_FILE}" "${BASELINE_FILE}" "${TMP_DELTA}"
else
  python3 - <<PY
import numpy as np
import xarray as xr

baseline_file = "${BASELINE_FILE}"
future_file = "${FUTURE_FILE}"
tmp_delta = "${TMP_DELTA}"
requested_var = "${VAR}"
delta_mode = "${DELTA_MODE}"
log_ratio_floor = float("${LOG_RATIO_FLOOR}")
log_ratio_invalid_policy = "${LOG_RATIO_INVALID_POLICY}"
log_ratio_min_factor = float("${LOG_RATIO_MIN_FACTOR}")
log_ratio_max_factor = float("${LOG_RATIO_MAX_FACTOR}")

if log_ratio_floor < 0:
    raise ValueError(f"LOG_RATIO_FLOOR must be non-negative, got {log_ratio_floor}")
if log_ratio_min_factor < 0:
    raise ValueError(
        f"LOG_RATIO_MIN_FACTOR must be non-negative, got {log_ratio_min_factor}"
    )
if log_ratio_max_factor <= 0:
    raise ValueError(
        f"LOG_RATIO_MAX_FACTOR must be positive, got {log_ratio_max_factor}"
    )
if log_ratio_min_factor > log_ratio_max_factor:
    raise ValueError(
        "LOG_RATIO_MIN_FACTOR cannot exceed LOG_RATIO_MAX_FACTOR: "
        f"{log_ratio_min_factor} > {log_ratio_max_factor}"
    )

def pick_main_var(ds, requested=None):
    if requested and requested in ds.data_vars:
        return requested
    candidates = [
        name for name in ds.data_vars
        if "bnds" not in name.lower() and "bounds" not in name.lower()
    ]
    if not candidates:
        raise ValueError(f"No valid data variable found in dataset: {list(ds.data_vars)}")
    return candidates[0]

with xr.open_dataset(baseline_file) as ds_base, xr.open_dataset(future_file) as ds_future:
    base_var = pick_main_var(ds_base, requested_var)
    future_var = pick_main_var(ds_future, requested_var)
    if base_var != future_var:
        raise ValueError(f"Baseline/future variable mismatch: {base_var} vs {future_var}")

    da_base = ds_base[base_var]
    da_future = ds_future[future_var]
    if set(da_base.dims) != set(da_future.dims):
        raise ValueError(
            f"Baseline/future dimensions differ: {da_base.dims} vs {da_future.dims}"
        )
    da_base = da_base.transpose(*da_future.dims)
    if da_base.shape != da_future.shape:
        raise ValueError(
            f"Baseline/future shapes differ after transpose: {da_base.shape} vs {da_future.shape}"
        )

    future_values = np.asarray(da_future.values, dtype=float)
    base_values = np.asarray(da_base.values, dtype=float)
    finite = np.isfinite(future_values) & np.isfinite(base_values)
    positive = (future_values > 0) & (base_values > 0)
    above_floor = (future_values >= log_ratio_floor) & (base_values >= log_ratio_floor)
    source_valid = finite & positive & above_floor
    factor = np.full(future_values.shape, np.nan, dtype=float)
    factor[source_valid] = future_values[source_valid] / base_values[source_valid]
    below_min_factor = source_valid & (factor < log_ratio_min_factor)
    above_max_factor = source_valid & (factor > log_ratio_max_factor)
    factor_rejected = below_min_factor | above_max_factor
    valid = source_valid & ~factor_rejected
    no_change = np.zeros(future_values.shape, dtype=bool)
    delta_values = np.full(future_values.shape, np.nan, dtype=float)
    delta_values[valid] = np.log(future_values[valid]) - np.log(base_values[valid])
    if log_ratio_invalid_policy == "no_change":
        # Preserve the existing treatment of finite nonpositive/floored source
        # values. Factor-bound failures are deliberately missing so an unstable
        # multiplicative change cannot contribute a baseline/no-change value.
        no_change = finite & ~source_valid
        delta_values[no_change] = 0.0
    missing = ~np.isfinite(delta_values)
    da_delta = xr.DataArray(
        delta_values,
        coords=da_future.coords,
        dims=da_future.dims,
        name=future_var,
    )
    da_delta.attrs = da_future.attrs.copy()
    da_delta.attrs.update({
        "delta_mode": delta_mode,
        "delta_formula": "log(future) - log(baseline)",
        "log_ratio_floor": log_ratio_floor,
        "invalid_log_ratio_policy": log_ratio_invalid_policy,
        "log_ratio_min_factor": log_ratio_min_factor,
        "log_ratio_max_factor": log_ratio_max_factor,
        "log_ratio_factor_policy": "outside inclusive bounds is missing",
        "log_ratio_policy_note": (
            "missing leaves invalid/floored cells as missing; no_change sets "
            "finite invalid/floored cells to zero log change; factor-bound "
            "failures remain missing under either policy"
        ),
        "log_ratio_valid_cells": int(valid.sum()),
        "log_ratio_below_min_factor_cells": int(below_min_factor.sum()),
        "log_ratio_above_max_factor_cells": int(above_max_factor.sum()),
        "log_ratio_factor_rejected_cells": int(factor_rejected.sum()),
        "log_ratio_no_change_cells": int(no_change.sum()),
        "log_ratio_missing_cells": int(missing.sum()),
        "units": "1",
    })
    qc_mask_name = f"{future_var}_log_ratio_qc_valid"
    da_qc_mask = xr.DataArray(
        (~factor_rejected).astype(np.int8),
        coords=da_future.coords,
        dims=da_future.dims,
        name=qc_mask_name,
        attrs={
            "long_name": "Log-ratio factor quality-control validity mask",
            "flag_values": np.array([0, 1], dtype=np.int8),
            "flag_meanings": "factor_rejected factor_accepted_or_not_evaluated",
            "qc_min_factor": log_ratio_min_factor,
            "qc_max_factor": log_ratio_max_factor,
            "comment": (
                "Zero identifies a positive finite source cell rejected solely "
                "because its future-to-historical factor was outside the inclusive bounds."
            ),
        },
    )
    print(f"LOG RATIO FLOOR          : {log_ratio_floor}")
    print(f"LOG RATIO POLICY         : {log_ratio_invalid_policy}")
    print(f"LOG RATIO FACTOR BOUNDS  : {log_ratio_min_factor} to {log_ratio_max_factor}")
    print(f"LOG RATIO FINITE CELLS   : {int(finite.sum())}")
    print(f"LOG RATIO VALID CELLS    : {int(valid.sum())}")
    print(f"LOG RATIO BELOW MIN      : {int(below_min_factor.sum())}")
    print(f"LOG RATIO ABOVE MAX      : {int(above_max_factor.sum())}")
    print(f"LOG RATIO FACTOR REJECTED: {int(factor_rejected.sum())}")
    print(f"LOG RATIO NO-CHANGE CELLS: {int(no_change.sum())}")
    print(f"LOG RATIO MISSING CELLS  : {int(missing.sum())}")

    ds_out = ds_future.copy(deep=True)
    ds_out[future_var] = da_delta
    ds_out[qc_mask_name] = da_qc_mask
    ds_out.attrs = ds_future.attrs.copy()
    ds_out.attrs.update({
        "delta_mode": delta_mode,
        "delta_baseline_file": baseline_file,
        "delta_future_file": future_file,
        "log_ratio_qc_mask_variable": qc_mask_name,
    })
    ds_out.to_netcdf(tmp_delta, format="NETCDF4")
PY
fi
finalize_delta "$TMP_DELTA"
mv -f "${TMP_DELTA}" "${DELTA_FILE}"
echo "[DONE ] ${DELTA_FILE}"

if [[ "$REGRID_DELTA" == "yes" ]]; then
  REGRID_FILE="${REGRID_OUT_DIR}/${OUT_PREFIX}_delta_${FUTURE_TAG}_minus_${BASELINE_TAG}_${REGRID_SUFFIX}.nc"
  TMP_REGRID="${TMP_DIR}/${OUT_PREFIX}_delta_${FUTURE_TAG}_minus_${BASELINE_TAG}_${REGRID_SUFFIX}.tmp.nc"

  QC_MASK_NAME="${VAR}_log_ratio_qc_valid"
  TMP_REGRID_DATA="${TMP_DIR}/${OUT_PREFIX}_delta_${FUTURE_TAG}_minus_${BASELINE_TAG}_${REGRID_SUFFIX}.data.tmp.nc"
  TMP_REGRID_MASK="${TMP_DIR}/${OUT_PREFIX}_delta_${FUTURE_TAG}_minus_${BASELINE_TAG}_${REGRID_SUFFIX}.mask.tmp.nc"
  TMP_REGRID_MASKED="${TMP_DIR}/${OUT_PREFIX}_delta_${FUTURE_TAG}_minus_${BASELINE_TAG}_${REGRID_SUFFIX}.masked.tmp.nc"

  rm -f "${TMP_REGRID}" "${TMP_REGRID_DATA}" "${TMP_REGRID_MASK}" "${TMP_REGRID_MASKED}"

  echo "[STEP3] Regridding delta"
  if cdo -s showname "${DELTA_FILE}" | tr ' ' '\n' | grep -Fxq "${QC_MASK_NAME}"; then
    # The scientific delta follows the configured interpolation, while the
    # categorical QC mask uses nearest-neighbor remapping. Reapply the mask
    # after interpolation so rejected source cells cannot be reconstructed.
    cdo -L -O ${CDO_OUTPUT_ARGS[@]+"${CDO_OUTPUT_ARGS[@]}"} ${METHOD},"${GRIDFILE}" -delname,"${QC_MASK_NAME}" "${DELTA_FILE}" "${TMP_REGRID_DATA}"
    cdo -L -O ${CDO_OUTPUT_ARGS[@]+"${CDO_OUTPUT_ARGS[@]}"} remapnn,"${GRIDFILE}" -selname,"${QC_MASK_NAME}" "${DELTA_FILE}" "${TMP_REGRID_MASK}"
    cdo -L -O ${CDO_OUTPUT_ARGS[@]+"${CDO_OUTPUT_ARGS[@]}"} ifthen "${TMP_REGRID_MASK}" "${TMP_REGRID_DATA}" "${TMP_REGRID_MASKED}"
    cdo -L -O ${CDO_OUTPUT_ARGS[@]+"${CDO_OUTPUT_ARGS[@]}"} merge "${TMP_REGRID_MASKED}" "${TMP_REGRID_MASK}" "${TMP_REGRID}"
    rm -f "${TMP_REGRID_DATA}" "${TMP_REGRID_MASK}" "${TMP_REGRID_MASKED}"
  else
    cdo -L -O ${CDO_OUTPUT_ARGS[@]+"${CDO_OUTPUT_ARGS[@]}"} ${METHOD},"${GRIDFILE}" "${DELTA_FILE}" "${TMP_REGRID}"
  fi
  finalize_delta "$TMP_REGRID"
  mv -f "${TMP_REGRID}" "${REGRID_FILE}"
  echo "[DONE ] ${REGRID_FILE}"
fi

echo
echo "All climatology delta processing completed for VAR=${VAR}"
