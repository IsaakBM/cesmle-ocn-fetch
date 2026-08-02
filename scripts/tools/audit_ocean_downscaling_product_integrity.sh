#!/usr/bin/env bash
# ==============================================================================
#  Audit curated ocean downscaling product filename/path/time consistency
# ==============================================================================

set -euo pipefail

PRODUCT_ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
OUT_FILE="${OUT_FILE:-data/manifests/ocean_downscaling_product_integrity_audit.csv}"
FUTURE_MODELS="${FUTURE_MODELS:-auto}"
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS:-cesm_f09_g16 legacy_downscaled_rcp85}"
SCENARIOS="${SCENARIOS:-auto}"
VARS="${VARS:-auto}"
WINDOWS="${WINDOWS:-auto}"
RESOLUTIONS="${RESOLUTIONS:-auto}"
INCLUDE_BASELINE="${INCLUDE_BASELINE:-yes}"
INCLUDE_FUTURE="${INCLUDE_FUTURE:-yes}"
COMPUTE_STATS="${COMPUTE_STATS:-no}"
FAIL_ON_ISSUE="${FAIL_ON_ISSUE:-no}"

mkdir -p "$(dirname "${OUT_FILE}")"

python3 - <<'PY' "${PRODUCT_ROOT}" "${OUT_FILE}" "${FUTURE_MODELS}" "${EXCLUDE_FUTURE_MODELS}" "${SCENARIOS}" "${VARS}" "${WINDOWS}" "${RESOLUTIONS}" "${INCLUDE_BASELINE}" "${INCLUDE_FUTURE}" "${COMPUTE_STATS}" "${FAIL_ON_ISSUE}"
import csv
import math
import re
import sys
from pathlib import Path

import numpy as np

try:
    import xarray as xr
except ModuleNotFoundError as exc:
    raise SystemExit(
        "ERROR: Python module xarray is required for this audit. "
        "Run on the same environment used by the NetCDF processing pipeline."
    ) from exc

(
    product_root,
    out_file,
    future_models_text,
    exclude_models_text,
    scenarios_text,
    vars_text,
    windows_text,
    resolutions_text,
    include_baseline,
    include_future,
    compute_stats,
    fail_on_issue,
) = sys.argv[1:]

root = Path(product_root)
future_model_filter = None if future_models_text == "auto" else set(future_models_text.split())
exclude_models = set(exclude_models_text.split())
scenario_filter = None if scenarios_text == "auto" else set(scenarios_text.split())
var_filter = None if vars_text == "auto" else set(vars_text.split())
window_filter = None if windows_text == "auto" else set(windows_text.split())
resolution_filter = None if resolutions_text == "auto" else set(resolutions_text.split())
include_baseline = include_baseline == "yes"
include_future = include_future == "yes"
compute_stats = compute_stats == "yes"
fail_on_issue = fail_on_issue == "yes"

ignored_vars = {"time_bnds", "lat_bnds", "lon_bnds", "depth_bnds", "lev_bnds", "z_t_bnds", "bnds"}

def contains_token(filename, token):
    if not token:
        return True
    parts = re.split(r"[/_.-]+", filename)
    return token in parts or token in filename

def token_text_for_record(path, filename, record, label):
    scopes = record.get("token_search_scope", {})
    scope = scopes.get(label, "filename")
    if scope == "path":
        return str(path)
    return filename

def pick_main_var(ds, expected):
    if expected in ds.data_vars:
        return expected
    candidates = [v for v in ds.data_vars if v not in ignored_vars and "bnds" not in v.lower()]
    if len(candidates) == 1:
        return candidates[0]
    if candidates:
        return candidates[0]
    return ""

def numeric_years(values):
    years = []
    for value in np.ravel(values):
        if value is None:
            continue
        try:
            if np.isnat(value):
                continue
        except TypeError:
            pass
        text = str(value)
        match = re.match(r"^([0-9]{4})", text)
        if match:
            years.append(int(match.group(1)))
    return years

def stat_text(arr, fn):
    finite = np.asarray(arr.values, dtype=float)
    finite = finite[np.isfinite(finite)]
    if finite.size == 0:
        return ""
    return f"{fn(finite):.12g}"

def audit_one(path, record):
    notes = []
    status = "ok"
    filename = path.name
    expected_var = record["var"]
    expected_scenario = record["scenario"]
    expected_window = record["window"]
    expected_resolution = record["resolution"]

    try:
        with xr.open_dataset(path) as ds:
            main_var = pick_main_var(ds, expected_var)
            dims = ";".join(f"{k}={v}" for k, v in ds.sizes.items())
            units = str(ds[main_var].attrs.get("units", "")) if main_var else ""
            standard_name = str(ds[main_var].attrs.get("standard_name", "")) if main_var else ""
            time_size = int(ds.sizes.get("time", 0))
            time_values = ""
            time_min_year = ""
            time_max_year = ""
            bnds_min_year = ""
            bnds_max_year = ""

            if main_var != expected_var:
                status = "content_mismatch"
                notes.append(f"main variable {main_var!r} does not match expected {expected_var!r}")

            if "time" in ds:
                years = numeric_years(ds["time"].values)
                time_values = "|".join(str(v) for v in np.ravel(ds["time"].values)[:6])
                if years:
                    time_min_year = min(years)
                    time_max_year = max(years)
            else:
                status = "missing_time" if status == "ok" else status
                notes.append("missing time coordinate")

            if "time_bnds" in ds:
                bnd_years = numeric_years(ds["time_bnds"].values)
                if bnd_years:
                    bnds_min_year = min(bnd_years)
                    bnds_max_year = max(bnd_years)

            if expected_window:
                try:
                    start_year, end_year = [int(x) for x in expected_window.split("-", 1)]
                    if time_min_year != "":
                        if not (start_year <= int(time_min_year) <= end_year and start_year <= int(time_max_year) <= end_year):
                            status = "time_outside_window"
                            notes.append(
                                f"time years {time_min_year}-{time_max_year} outside expected {expected_window}"
                            )
                    if bnds_min_year != "":
                        if int(bnds_min_year) != start_year or int(bnds_max_year) != end_year:
                            status = "time_bounds_mismatch"
                            notes.append(
                                f"time_bnds years {bnds_min_year}-{bnds_max_year} do not match expected {expected_window}"
                            )
                    else:
                        if status == "ok":
                            status = "missing_time_bounds"
                        notes.append("missing time_bnds for windowed climatology")
                except ValueError:
                    notes.append(f"could not parse expected window {expected_window!r}")

            for label, token in (
                ("scenario", expected_scenario),
                ("variable", expected_var),
                ("window", expected_window),
                ("resolution", expected_resolution),
            ):
                token_text = token_text_for_record(path, filename, record, label)
                if token and not contains_token(token_text, token):
                    if status == "ok":
                        status = "filename_mismatch"
                    notes.append(f"{record.get('token_search_scope', {}).get(label, 'filename')} does not contain {label} token {token!r}")

            ncells = min_value = max_value = mean_value = ""
            if compute_stats and main_var:
                data = ds[main_var]
                ncells = int(np.isfinite(np.asarray(data.values, dtype=float)).sum())
                min_value = stat_text(data, np.min)
                max_value = stat_text(data, np.max)
                mean_value = stat_text(data, np.mean)

    except Exception as exc:
        main_var = ""
        dims = units = standard_name = time_values = ""
        time_size = time_min_year = time_max_year = bnds_min_year = bnds_max_year = ""
        ncells = min_value = max_value = mean_value = ""
        status = "read_error"
        notes = [str(exc)]

    row = {k: v for k, v in record.items() if k != "token_search_scope"}
    row.update({
        "file": str(path),
        "filename": filename,
        "main_var": main_var,
        "dims": dims,
        "time_size": time_size,
        "time_values": time_values,
        "time_min_year": time_min_year,
        "time_max_year": time_max_year,
        "time_bnds_min_year": bnds_min_year,
        "time_bnds_max_year": bnds_max_year,
        "units": units,
        "standard_name": standard_name,
        "ncells": ncells,
        "min": min_value,
        "max": max_value,
        "mean": mean_value,
        "status": status,
        "notes": "; ".join(notes),
    })
    return row

records = []

if include_baseline:
    baseline_root = root / "baseline"
    if baseline_root.exists():
        for path in sorted(baseline_root.glob("*/*/*.nc")):
            rel = path.relative_to(root)
            _, var, resolution = rel.parts[:3]
            if var_filter is not None and var not in var_filter:
                continue
            if resolution_filter is not None and resolution not in resolution_filter:
                continue
            records.append(audit_one(path, {
                "scope": "baseline",
                "model": "",
                "member_or_stat": "",
                "scenario": "",
                "var": var,
                "window": "2006-2014",
                "resolution": resolution,
                "token_search_scope": {"resolution": "path"},
            }))

if include_future:
    future_root = root / "future"
    if future_root.exists():
        for path in sorted(future_root.glob("*/*/*/*/*/*/*.nc")):
            rel = path.relative_to(future_root)
            model, member, scenario, var, window, resolution = rel.parts[:6]
            if model in exclude_models:
                continue
            if future_model_filter is not None and model not in future_model_filter:
                continue
            if scenario_filter is not None and scenario not in scenario_filter:
                continue
            if var_filter is not None and var not in var_filter:
                continue
            if window_filter is not None and window not in window_filter:
                continue
            if resolution_filter is not None and resolution not in resolution_filter:
                continue
            records.append(audit_one(path, {
                "scope": "future",
                "model": model,
                "member_or_stat": member,
                "scenario": scenario,
                "var": var,
                "window": window,
                "resolution": resolution,
            }))

fieldnames = [
    "scope", "model", "member_or_stat", "scenario", "var", "window", "resolution",
    "file", "filename", "main_var", "dims", "time_size", "time_values",
    "time_min_year", "time_max_year", "time_bnds_min_year", "time_bnds_max_year",
    "units", "standard_name", "ncells", "min", "max", "mean", "status", "notes",
]

with open(out_file, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(records)

print(f"Wrote product integrity audit: {out_file}")
print(f"Files inspected: {len(records)}")
counts = {}
for row in records:
    counts[row["status"]] = counts.get(row["status"], 0) + 1
for status, count in sorted(counts.items()):
    print(f"{status}: {count}")

if fail_on_issue and any(row["status"] in {"time_outside_window", "content_mismatch", "filename_mismatch", "read_error"} for row in records):
    sys.exit(2)
PY
