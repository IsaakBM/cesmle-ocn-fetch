#!/usr/bin/env bash
# ==============================================================================
# Record release provenance without changing inputs or scientific products.
#
# Usage: SETTINGS_FILE=effective_settings.json OUT_FILE=release.json \
#          bash scripts/tools/record_ocean_pipeline_release.sh <file-or-directory> ...
# SETTINGS_FILE is a JSON object recording the effective scientific/run settings.
# Include source manifests, validation reports, and products among the arguments.
# File hashing can take time for a large release; run on an appropriate cluster job.
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
: "${SETTINGS_FILE:?Set SETTINGS_FILE to the reviewed effective-settings JSON object}"
: "${OUT_FILE:?Set OUT_FILE to a new release provenance JSON path}"
(( $# > 0 )) || { echo "ERROR: Provide release inputs, manifests, reports, or product paths" >&2; exit 1; }

# ------------------------------------------------------------------------------
# Capture immutable file identities, exact working code, supplied settings, and
# software versions. Write the report exclusively so older releases are preserved.
# ------------------------------------------------------------------------------
python3 - "${REPO_ROOT}" "${SETTINGS_FILE}" "${OUT_FILE}" "$@" <<'PY_RELEASE'
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import subprocess
import sys

repo, settings_path, output, *sources = sys.argv[1:]
repo, settings_path, output = Path(repo), Path(settings_path), Path(output)
settings = json.loads(settings_path.read_text())
if not isinstance(settings, dict) or not settings:
    raise SystemExit("ERROR: SETTINGS_FILE must contain a nonempty JSON object of effective settings")
if output.exists():
    raise SystemExit(f"ERROR: Preserve existing release record: {output}")

def command(args):
    try:
        result = subprocess.run(args, cwd=repo, text=True, capture_output=True, timeout=30)
        return {"exit_code": result.returncode, "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"unavailable": str(exc)}

def identity(path):
    before = path.stat()
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            digest.update(block)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise RuntimeError(f"File changed while hashing: {path}")
    return {"path": str(path.resolve()), "bytes": after.st_size, "sha256": digest.hexdigest()}

paths = set()
for source in sources:
    path = Path(source)
    if not path.exists():
        raise SystemExit(f"ERROR: Missing release path: {path}")
    paths.update(p.resolve() for p in path.rglob('*') if p.is_file()) if path.is_dir() else paths.add(path.resolve())
if output.resolve() in paths:
    raise SystemExit("ERROR: Output report must not be one of its own inputs")
files = [identity(path) for path in sorted(paths)]
packages = {}
for name in ('numpy', 'xarray', 'netCDF4', 'cftime', 'pandas', 'rasterio'):
    try:
        packages[name] = importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        packages[name] = None
record = {
    "schema_version": 1,
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "git_revision": command(['git', 'rev-parse', 'HEAD']),
    "git_status": command(['git', 'status', '--porcelain=v1']),
    "working_scripts": [identity(path) for path in sorted((repo/'scripts').rglob('*')) if path.is_file() and path.suffix in {'.sh', '.R', '.py'}],
    "settings_file": identity(settings_path),
    "effective_settings_supplied_by_operator": settings,
    "software": {name: command(args) for name, args in {
        'python': [sys.executable, '--version'], 'cdo': ['cdo', '-V'],
        'nco': ['ncks', '--version'], 'gdal': ['gdalinfo', '--version'],
        'R': ['Rscript', '--version'], 'bash': ['bash', '--version']}.items()},
    "python_packages": packages,
    "files": files,
    "validation_note": "Provenance is not a validation pass. Include separately generated validation reports and the expected-product list; settings must describe the actual run.",
}
output.parent.mkdir(parents=True, exist_ok=True)
with output.open('x') as stream:
    json.dump(record, stream, indent=2)
    stream.write('\n')
print(f"Recorded {len(files)} input/product/report identities: {output}")
PY_RELEASE
