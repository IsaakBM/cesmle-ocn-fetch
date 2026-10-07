#!/usr/bin/env python3
# ==============================================================================
#  Audit source coverage for monthly and season-ready climatologies
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Inspect source files without modifying or downloading them
#    - Verify the calendar-month windows and preceding Decembers required for
#      the planned 13-field monthly climatology products
#    - Distinguish ESGF manifest availability, raw downloads, and prepared
#      monthly inputs
#    - Audit GLORYS and biogeochemistry-hindcast baseline inputs separately
#    - Write one reviewable CSV row per dataset/variable/product window
# ==============================================================================

"""Read-only source-coverage audit for the climatology expansion plan."""

import collections
import csv
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


# ==============================================================================
# Configuration
# ==============================================================================
REPO_ROOT = Path(__file__).resolve().parents[2]

IPCC_DOWNLOAD_ROOT = Path(
    os.environ.get("IPCC_DOWNLOAD_ROOT", "/home/SB5/ipcc_esgf/downloads")
)
IPCC_LEGACY_DOWNLOAD_ROOT = Path(
    os.environ.get("IPCC_LEGACY_DOWNLOAD_ROOT", "/home/SB5/ipcc_esgf_downloads")
)
IPCC_MONTHLY_ROOT = Path(
    os.environ.get("IPCC_MONTHLY_ROOT", "/home/SB5/ipcc_esgf/monthly_1deg")
)
GLORYS_ROOT = Path(
    os.environ.get(
        "GLORYS_ROOT", "/home/SB5/reanalysis/glorys12v1/monthly_0p05"
    )
)
HINDCAST_ROOT = Path(
    os.environ.get(
        "HINDCAST_ROOT",
        "/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25",
    )
)
MANIFEST = Path(
    os.environ.get(
        "MANIFEST",
        str(
            REPO_ROOT
            / "data/manifests/ipcc_esgf_nci_cmip6_ocean_plus_siconc_wget_manifest.csv"
        ),
    )
)
OUT_FILE = Path(
    os.environ.get(
        "OUT_FILE",
        str(REPO_ROOT / "data/manifests/climatology_source_coverage_audit.csv"),
    )
)


def split_env(name, default):
    """Return a comma/space-separated environment variable as a list."""
    value = os.environ.get(name, "").strip()
    if not value:
        return list(default)
    return [item for item in re.split(r"[\s,]+", value) if item]


MODELS = split_env(
    "MODELS",
    (
        "CNRM-ESM2-1",
        "IPSL-CM6A-LR",
        "MPI-ESM1-2-HR",
        "MPI-ESM1-2-LR",
        "UKESM1-0-LL",
    ),
)
SCENARIOS = split_env("SCENARIOS", ("historical", "ssp126", "ssp245", "ssp585"))
IPCC_VARS = split_env(
    "IPCC_VARS",
    ("thetao", "so", "ph", "o2", "chl", "uo", "vo", "zooc", "zos", "mlotst", "siconc"),
)
GLORYS_VARS = split_env(
    "GLORYS_VARS", ("bottomT", "mlotst", "so", "thetao", "uo", "vo", "zos", "siconc")
)
HINDCAST_VARS = split_env(
    "HINDCAST_VARS", ("chl", "no3", "po4", "si", "o2", "nppv", "fe", "ph", "phyc")
)

VARS_2D = {"zos", "mlotst", "siconc"}
SUPPORTED_CALENDARS = {
    "standard": "standard",
    "gregorian": "standard",
    "proleptic_gregorian": "proleptic_gregorian",
    "julian": "julian",
    "noleap": "365_day",
    "365_day": "365_day",
    "all_leap": "366_day",
    "366_day": "366_day",
    "360_day": "360_day",
}

# Each interval includes the standard calendar window plus the additional
# preceding December needed for the season-year convention. The final December
# is retained for the normal January-December monthly climatology.
WINDOWS = {
    "historical": (("2006-2014", "2005-12", "2014-12"),),
    "future": (
        ("2030-2040", "2029-12", "2040-12"),
        ("2050-2060", "2049-12", "2060-12"),
        ("2090-2100", "2089-12", "2100-12"),
    ),
}

TIMESTAMP_RE = re.compile(
    r"(?P<year>\d{4,})-(?P<month>\d{2})-(?P<day>\d{2})"
    r"T\d{2}:\d{2}:\d{2}(?:\.\d+)?"
)
RANGE_RE = re.compile(r"(?<!\d)(\d{4})(\d{2})-(\d{4})(\d{2})(?!\d)")
CALENDAR_RE = re.compile(r"\btime:calendar\s*=\s*\"([^\"]+)\"")


# ==============================================================================
# Month and file helpers
# ==============================================================================
def month_index(value):
    """Convert YYYY-MM to a sortable integer month index."""
    match = re.fullmatch(r"(\d{4})-(\d{2})", value)
    if not match:
        raise ValueError("Invalid YYYY-MM value: {}".format(value))
    year, month = map(int, match.groups())
    if not 1 <= month <= 12:
        raise ValueError("Invalid month: {}".format(value))
    return year * 12 + month - 1


def month_label(index):
    """Convert an integer month index back to YYYY-MM."""
    return "{:04d}-{:02d}".format(index // 12, index % 12 + 1)


def expected_months(start, end):
    """Return every inclusive month between two YYYY-MM values."""
    first = month_index(start)
    last = month_index(end)
    if first > last:
        raise ValueError("Window starts after it ends: {} to {}".format(start, end))
    return set(range(first, last + 1))


def file_range(path):
    """Read the last YYYYMM-YYYYMM range encoded in a filename."""
    matches = list(RANGE_RE.finditer(path.name))
    if not matches:
        return None
    match = matches[-1]
    start = int(match.group(1)) * 12 + int(match.group(2)) - 1
    end = int(match.group(3)) * 12 + int(match.group(4)) - 1
    return start, end


def overlapping_files(paths, start, end):
    """Use filename ranges to avoid opening clearly irrelevant time chunks."""
    first = month_index(start)
    last = month_index(end)
    selected = []
    for path in paths:
        encoded = file_range(path)
        if encoded is None or (encoded[0] <= last and encoded[1] >= first):
            selected.append(path)
    return selected


def netcdf_calendar(path):
    """Read the CF time calendar; an absent attribute means standard calendar."""
    result = subprocess.run(
        ["ncdump", "-h", str(path)], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        return "", "ncdump failed: {}".format(result.stderr.strip())
    match = CALENDAR_RE.search(result.stdout)
    value = match.group(1).strip().lower() if match else "standard"
    return value, ""


FILE_CACHE = {}


def inspect_netcdf(path):
    """Return decoded year/month timestamps and calendar for one NetCDF file."""
    key = str(path.resolve())
    if key in FILE_CACHE:
        return FILE_CACHE[key]

    result = subprocess.run(
        ["cdo", "-s", "showtimestamp", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        value = ([], "", "cdo showtimestamp failed: {}".format(result.stderr.strip()))
        FILE_CACHE[key] = value
        return value

    months = []
    for match in TIMESTAMP_RE.finditer(result.stdout):
        year = int(match.group("year"))
        month = int(match.group("month"))
        day = int(match.group("day"))
        if not 1 <= month <= 12 or not 1 <= day <= 31:
            value = ([], "", "invalid decoded timestamp in {}".format(path))
            FILE_CACHE[key] = value
            return value
        months.append(year * 12 + month - 1)

    if not months:
        value = ([], "", "no decoded timestamps")
        FILE_CACHE[key] = value
        return value

    calendar, error = netcdf_calendar(path)
    value = (months, calendar, error)
    FILE_CACHE[key] = value
    return value


def inspect_paths(paths, start, end):
    """Summarize actual timestamp coverage for a group of NetCDF files."""
    relevant = overlapping_files(sorted(set(paths)), start, end)
    expected = expected_months(start, end)
    occurrences = collections.defaultdict(list)
    calendars = set()
    unreadable = []

    for path in relevant:
        months, calendar, error = inspect_netcdf(path)
        if error:
            unreadable.append("{}: {}".format(path, error))
            continue
        calendars.add(calendar)
        for value in months:
            if value in expected:
                occurrences[value].append(str(path))

    missing = sorted(expected - set(occurrences))
    duplicates = sorted(value for value, sources in occurrences.items() if len(sources) > 1)
    normalized = {SUPPORTED_CALENDARS.get(value, "unsupported:{}".format(value)) for value in calendars}

    return {
        "files": relevant,
        "timestamp_count": sum(len(sources) for sources in occurrences.values()),
        "unique_month_count": len(occurrences),
        "missing": missing,
        "duplicates": duplicates,
        "calendars": sorted(calendars),
        "normalized_calendars": sorted(normalized),
        "unreadable": unreadable,
        "complete": not missing and not duplicates and not unreadable and len(normalized) == 1
        and not next(iter(normalized), "").startswith("unsupported:"),
    }


def manifest_coverage(rows, start, end):
    """Summarize filename-range coverage and checksum conflicts in manifest rows."""
    expected = expected_months(start, end)
    occurrences = collections.defaultdict(list)
    unparsed = []
    checksums = collections.defaultdict(set)

    for row in rows:
        filename = row.get("filename", "")
        encoded = file_range(Path(filename))
        if encoded is None:
            unparsed.append(filename)
            continue
        first, last = encoded
        for value in range(max(first, min(expected)), min(last, max(expected)) + 1):
            if value in expected:
                occurrences[value].append(filename)
        checksums[filename].add(
            "{}:{}".format(row.get("checksum_type", "").lower(), row.get("checksum", "").lower())
        )

    conflicts = sorted(name for name, values in checksums.items() if len(values) > 1)
    missing = sorted(expected - set(occurrences))
    duplicates = sorted(
        value for value, filenames in occurrences.items() if len(set(filenames)) > 1
    )
    return {
        "row_count": len(rows),
        "missing": missing,
        "duplicates": duplicates,
        "unparsed": unparsed,
        "conflicts": conflicts,
        "complete": bool(rows)
        and not missing
        and not duplicates
        and not unparsed
        and not conflicts,
    }


def format_months(values):
    """Write month lists compactly but explicitly for review."""
    return ";".join(month_label(value) for value in values)


def format_list(values):
    """Write arbitrary values as a semicolon-delimited CSV field."""
    return ";".join(str(value) for value in values)


def find_files(directories, pattern):
    """Collect matching files from existing candidate directories."""
    files = []
    existing = []
    for directory in directories:
        if directory.is_dir():
            existing.append(directory)
            files.extend(path for path in directory.glob(pattern) if path.is_file())
    return sorted(set(files)), existing


# ==============================================================================
# Expected CMIP groups and path resolution
# ==============================================================================
def read_manifest():
    """Read and validate the ESGF wget manifest."""
    if not MANIFEST.is_file():
        raise SystemExit("ERROR: Manifest not found: {}".format(MANIFEST))
    with MANIFEST.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    required = {
        "filename",
        "checksum_type",
        "checksum",
        "source_id",
        "experiment_id",
        "member_id",
        "variable_id",
    }
    missing = sorted(required - set(rows[0] if rows else ()))
    if missing:
        raise SystemExit("ERROR: Manifest missing columns: {}".format(", ".join(missing)))
    return rows


def manifest_group(rows, model, scenario, variable):
    """Select manifest rows for one production model/scenario/variable."""
    return [
        row
        for row in rows
        if row["source_id"] == model
        and row["experiment_id"] == scenario
        and row["variable_id"] == variable
    ]


def ipcc_directories(root, model, member, scenario, variable, stage=None):
    """Return current and tolerated legacy directories for one CMIP group."""
    suffix = (variable, stage) if stage else (variable,)
    return [
        root.joinpath(model, member, scenario, *suffix),
        root.joinpath(model, scenario, *suffix),
        root.joinpath(scenario, *suffix),
    ]


def classify_ipcc(prepared, raw, manifest):
    """Classify the most advanced complete state without hiding defects."""
    if prepared["unreadable"] or raw["unreadable"]:
        return "unreadable_files"
    if (
        prepared["duplicates"]
        or raw["duplicates"]
        or manifest["duplicates"]
        or manifest["conflicts"]
    ):
        return "duplicated_or_version_conflicted"
    if len(prepared["normalized_calendars"]) > 1 or any(
        value.startswith("unsupported:") for value in prepared["normalized_calendars"]
    ):
        return "calendar_conflict_or_unsupported"
    if prepared["complete"]:
        return "complete_and_prepared"
    if raw["complete"]:
        return "downloaded_complete_needs_preparation"
    if manifest["complete"]:
        return "available_in_manifest_needs_download_or_preparation"
    if manifest["row_count"]:
        return "partially_available_in_manifest"
    return "unavailable_in_current_manifest"


def base_record(dataset, model, member, scenario, variable, label, start, end):
    """Create stable identity and expected-window columns."""
    return {
        "dataset": dataset,
        "model": model,
        "member": member,
        "scenario": scenario,
        "variable": variable,
        "product_window": label,
        "required_start": start,
        "required_end": end,
        "expected_month_count": len(expected_months(start, end)),
        "preceding_december": start,
    }


def add_coverage(record, prefix, coverage, directories):
    """Add one actual-file coverage summary to a report row."""
    record.update(
        {
            prefix + "_directories": format_list(directories),
            prefix + "_file_count": len(coverage["files"]),
            prefix + "_timestamp_count": coverage["timestamp_count"],
            prefix + "_unique_month_count": coverage["unique_month_count"],
            prefix + "_missing_months": format_months(coverage["missing"]),
            prefix + "_duplicate_months": format_months(coverage["duplicates"]),
            prefix + "_calendars": format_list(coverage["calendars"]),
            prefix + "_unreadable": format_list(coverage["unreadable"]),
            prefix + "_complete": "yes" if coverage["complete"] else "no",
        }
    )


def audit_ipcc(manifest_rows):
    """Audit manifest, raw, and prepared CMIP6 coverage."""
    records = []
    for model in MODELS:
        for scenario in SCENARIOS:
            window_group = "historical" if scenario == "historical" else "future"
            for variable in IPCC_VARS:
                group_rows = manifest_group(manifest_rows, model, scenario, variable)
                members = sorted({row["member_id"] for row in group_rows}) or ["not_in_manifest"]
                for member in members:
                    member_rows = [row for row in group_rows if row["member_id"] == member]
                    stage = "parts" if variable in VARS_2D else "on_glorys"
                    pattern = (
                        "*.nc"
                        if member == "not_in_manifest"
                        else "{}_*_{}_{}_{}_*.nc".format(
                            variable, model, scenario, member
                        )
                    )
                    prepared_dirs = ipcc_directories(
                        IPCC_MONTHLY_ROOT, model, member, scenario, variable, stage
                    )
                    raw_dirs = ipcc_directories(
                        IPCC_DOWNLOAD_ROOT, model, member, scenario, variable
                    )
                    raw_dirs.extend(
                        ipcc_directories(
                            IPCC_LEGACY_DOWNLOAD_ROOT,
                            model,
                            member,
                            scenario,
                            variable,
                        )
                    )
                    prepared_files, existing_prepared_dirs = find_files(prepared_dirs, pattern)
                    raw_files, existing_raw_dirs = find_files(raw_dirs, pattern)

                    for label, start, end in WINDOWS[window_group]:
                        prepared = inspect_paths(prepared_files, start, end)
                        raw = inspect_paths(raw_files, start, end)
                        available = manifest_coverage(member_rows, start, end)
                        record = base_record(
                            "cmip6", model, member, scenario, variable, label, start, end
                        )
                        add_coverage(record, "prepared", prepared, existing_prepared_dirs)
                        add_coverage(record, "raw", raw, existing_raw_dirs)
                        record.update(
                            {
                                "manifest_row_count": available["row_count"],
                                "manifest_missing_months": format_months(available["missing"]),
                                "manifest_duplicate_months": format_months(
                                    available["duplicates"]
                                ),
                                "manifest_unparsed_files": format_list(available["unparsed"]),
                                "manifest_checksum_conflicts": format_list(available["conflicts"]),
                                "manifest_complete": "yes" if available["complete"] else "no",
                                "classification": classify_ipcc(prepared, raw, available),
                            }
                        )
                        records.append(record)
    return records


def classify_baseline(coverage):
    """Classify GLORYS/hindcast coverage without inferring remote availability."""
    if coverage["unreadable"]:
        return "unreadable_files"
    if coverage["duplicates"]:
        return "duplicated_or_version_conflicted"
    if len(coverage["normalized_calendars"]) > 1 or any(
        value.startswith("unsupported:") for value in coverage["normalized_calendars"]
    ):
        return "calendar_conflict_or_unsupported"
    if coverage["complete"]:
        return "complete_and_prepared"
    if coverage["files"]:
        return "incomplete_prepared_source"
    return "source_directory_or_files_missing"


def audit_baseline(dataset, root, variables, stage):
    """Audit one trusted-reference baseline family."""
    records = []
    for variable in variables:
        directory = root / variable / stage
        files, existing_dirs = find_files([directory], "*.nc")
        for label, start, end in WINDOWS["historical"]:
            coverage = inspect_paths(files, start, end)
            record = base_record(
                dataset, dataset, "baseline", "historical", variable, label, start, end
            )
            add_coverage(record, "prepared", coverage, existing_dirs)
            add_coverage(record, "raw", inspect_paths([], start, end), [])
            record.update(
                {
                    "manifest_row_count": "",
                    "manifest_missing_months": "",
                    "manifest_duplicate_months": "",
                    "manifest_unparsed_files": "",
                    "manifest_checksum_conflicts": "",
                    "manifest_complete": "not_applicable",
                    "classification": classify_baseline(coverage),
                }
            )
            records.append(record)
    return records


# ==============================================================================
# Report writing and entry point
# ==============================================================================
FIELDNAMES = (
    "dataset",
    "model",
    "member",
    "scenario",
    "variable",
    "product_window",
    "required_start",
    "required_end",
    "preceding_december",
    "expected_month_count",
    "classification",
    "prepared_directories",
    "prepared_file_count",
    "prepared_timestamp_count",
    "prepared_unique_month_count",
    "prepared_missing_months",
    "prepared_duplicate_months",
    "prepared_calendars",
    "prepared_unreadable",
    "prepared_complete",
    "raw_directories",
    "raw_file_count",
    "raw_timestamp_count",
    "raw_unique_month_count",
    "raw_missing_months",
    "raw_duplicate_months",
    "raw_calendars",
    "raw_unreadable",
    "raw_complete",
    "manifest_row_count",
    "manifest_missing_months",
    "manifest_duplicate_months",
    "manifest_unparsed_files",
    "manifest_checksum_conflicts",
    "manifest_complete",
)


def require_commands():
    """Fail before scanning if NetCDF inspection commands are unavailable."""
    missing = [command for command in ("cdo", "ncdump") if shutil.which(command) is None]
    if missing:
        raise SystemExit("ERROR: Missing required commands: {}".format(", ".join(missing)))


def main():
    """Run the read-only audit and write its CSV report."""
    require_commands()
    manifest_rows = read_manifest()

    print("Auditing climatology source coverage (read-only)", file=sys.stderr)
    print("  CMIP downloads : {}".format(IPCC_DOWNLOAD_ROOT), file=sys.stderr)
    print("  CMIP legacy    : {}".format(IPCC_LEGACY_DOWNLOAD_ROOT), file=sys.stderr)
    print("  CMIP prepared  : {}".format(IPCC_MONTHLY_ROOT), file=sys.stderr)
    print("  GLORYS         : {}".format(GLORYS_ROOT), file=sys.stderr)
    print("  Hindcast       : {}".format(HINDCAST_ROOT), file=sys.stderr)
    print("  Manifest       : {}".format(MANIFEST), file=sys.stderr)

    records = []
    records.extend(audit_ipcc(manifest_rows))
    records.extend(audit_baseline("glorys12v1", GLORYS_ROOT, GLORYS_VARS, "parts"))
    records.extend(
        audit_baseline(
            "global_ocean_biogeochemistry_hindcast",
            HINDCAST_ROOT,
            HINDCAST_VARS,
            "on_glorys",
        )
    )

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUT_FILE.with_name(OUT_FILE.name + ".tmp")
    with temporary.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, extrasaction="raise")
        writer.writeheader()
        writer.writerows(records)
    os.replace(str(temporary), str(OUT_FILE))

    counts = collections.Counter(record["classification"] for record in records)
    print("Wrote {} audit rows to: {}".format(len(records), OUT_FILE), file=sys.stderr)
    for classification, count in sorted(counts.items()):
        print("  {:4d}  {}".format(count, classification), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
