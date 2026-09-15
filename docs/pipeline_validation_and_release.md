# Pipeline validation and release procedure

These safeguards keep the existing `scripts/core`, `scripts/tools`, and
`scripts/runners` layout and numerical methods. They do not regenerate existing
products or resolve scientific choices such as model weighting or coastal filling.

## What changed

| Area | Behavior |
| --- | --- |
| Monthly coverage | Both climatology workers require one actual timestep per requested month. Missing/duplicate months fail before processing. |
| Spatial identity | Delta and coastal addition validate dimension sizes, coordinate values/order, coordinate units, and vertical direction metadata before positional arithmetic. Climatology times may differ, but must be singleton when present. |
| External mask | A mask may broadcast across absent dimensions; coordinates it supplies must match. No grid conversion is performed by the validator. |
| Existing outputs | Climatology/delta/native-add temporary calculations retain the previous final file until promotion. This is per-file protection, not a transaction across all native/regridded products. |
| Downloads | Selected manifest conflicts/empty selections fail before download. Failed downloads return failure by default, and a failed final rename is no longer reported as success. |
| Organization | Each existing copy is compared to its source. Missing files in partial directories are copied; differing files fail unless `OVERWRITE=yes`. Copies use unique temporary files before promotion. |
| Integrity audit | `FAIL_ON_ISSUE=yes` is the default in the worker and runner. Empty selections and all reported issue statuses fail. |
| New-model preflight | Raw input timestamps, historical/future member pairing, source-unit consistency, and the existing `lev`/metre depth assumption are checked. |
| Stage coordination | The smoke helper rejects `RUN=yes STEP=all`. Dependent submissions require `PREVIOUS_JOB_IDS` with completed, successful Slurm jobs. |
| Release record | A standalone recorder hashes supplied inputs/products/reports and working scripts, and records supplied effective settings and software versions. |

Strict validation can stop a previously accepted run. That is a rejected-input or
incomplete-work signal, not proof that previously released results were wrong.
Do not automatically rename coordinates, convert units, fill missing months,
select conflicting dataset versions, or change members to bypass a failure.

## Daily inputs and protected preparation outputs

GLORYS download skipping now requires complete actual daily timestamps, not a
minimum filename count. The same calendar-aware check runs before daily-to-monthly
averaging in the temporal worker (`INPUT_TIMESTEP=daily`, including the GLORYS
runner, or the existing auto-selected daily mode). Missing, duplicate, mixed-calendar,
out-of-month, unreadable-time, and unsupported-calendar inputs stop processing.
Supported calendars are standard/Gregorian, proleptic Gregorian, Julian, no-leap,
all-leap, and 360-day, including their CF aliases. Existing monthly-input selection
and averaging/regridding settings are retained.

The downloader queues months with missing days, then checks coverage again after
the client finishes. Conflicting versions and old nested download layouts require
review; files are not flattened or versions chosen automatically. This needs
Python 3 with NumPy, netCDF4, and cftime in the download and processing environments.
Coverage validates timestamps, not scientific field quality.

Monthly preparation, time-series regridding, and vertical interpolation build
replacements in unique temporary workspaces beside their final files. They read
back the complete candidate with CDO and check variable names and timestamps;
vertical interpolation also checks configured target levels. A successful candidate
replaces the final file by a same-filesystem rename. Failed workers preserve the
previous final file, and their failure propagates to the job. Preparation therefore
needs working space on the output filesystem; `MIN_FREE_GB` checks that filesystem
in the temporal worker. The existing CDO defaults remain `/usr/bin/cdo` (temporal)
and `cdo` on PATH (vertical); `CDO` can select the executable explicitly.

An output-specific `.lock` directory rejects simultaneous writers. Downloaders
similarly lock each month. Normal exits and handled signals clean up owned locks
and workspaces. SIGKILL, node loss, or filesystem failures can leave them behind:
check the relevant jobs are no longer running before manually removing only the
stale lock/workspace. A lock is never automatically treated as stale. Protection
is per file, not a transaction across a complete run.

Missing vertical-axis descriptors are built privately for each invocation; existing
configured descriptors remain readable as before. `OVERWRITE_OUTPUTS=no` still
retains existing vertical outputs and explicitly reports that freshness was not
verified. Source/settings freshness checks remain separate work; protected exporter writes
are described below and do not certify existing products as current.

## Protected layer, depth, and delivery writes

The fine/pelagic layer tool, depth splitter, and CSV/Parquet/GeoTIFF exporters now
write replacements into unique temporary workspaces beside each destination. Each
output has an exclusive `.lock` directory. A writer never removes someone else's
lock, and only publishes its candidate after format-specific readback succeeds:

- NetCDF: read all fields and compare values, coordinates, attributes, and structure
  with the dataset prepared by the existing calculation. Unchanged 2D copies also
  use protected publication; the depth splitter verifies byte-for-byte copies.
- CSV/Parquet: reopen the table and compare columns, rows, and values with the
  prepared table (CSV uses a small floating-point round-trip tolerance).
- GeoTIFF: read all encoded pixels and check shape, dtype, nodata, transform, CRS,
  and variable/scale/offset metadata. CLI-only GDAL validation needs both
  `gdal_translate` and `gdalinfo` and temporary space for an ENVI readback.

Scientific calculations, table columns, raster encoding settings, filenames, and
final layouts are retained. Existing overwrite controls keep their meaning; the
CSV exporter and depth splitter still replace their outputs when run. These checks
add readback I/O and require space for the old file and its candidate. A failed
writer or validation leaves the previous final file intact and fails the job.
Protection is per output, not a transaction across all outputs from a source file.
Each generated delivery output also gets a sidecar fingerprint named
`<output>.provenance.json`. The sidecar records the source file path, source size,
source mtime, script identity, output path, and relevant export settings. When a
tool would keep an existing output because `OVERWRITE=no`, the sidecar must match
the current source/settings; missing or mismatched provenance fails the job and
preserves the existing output.

GeoTIFF runs sharing an output root also lock `geotiff_manifest.csv`. File workers
within a run remain parallel. Each run uses private manifest rows; worker failures
retain the previous manifest instead of being accepted merely because rows exist.
Completed TIFFs can remain after a later worker fails; the failed run must be
reviewed/rerun before treating its manifest as a complete account of those files.
Manifest publication uses an atomic rename on its destination filesystem.

GeoTIFF manifest rows now include `publication_status`: `validated_replacement`
for newly written/read-back TIFFs and `fresh_existing` for skipped TIFFs whose
sidecar provenance matches the current source and settings. Skipped TIFFs retain
previously recorded metadata where available; unknown fields stay blank rather
than being inferred from current settings.

## Planned adjustment sequence

Continue the repository adjustment work in this order:

1. Safe publication for preparation and delivery outputs.
   Daily coverage checks, preparation outputs, vertical interpolation outputs,
   layer/depth NetCDF products, CSV, Parquet, and GeoTIFF exports now publish
   through validated temporary candidates.
2. Naming and role reconciliation.
   Reassess active path names, runner names, headers, and README descriptions
   before adding freshness/provenance metadata. This pass must account for the
   current project decision that CESM/RCP85 is no longer part of the active or
   planned production pipeline.
3. Freshness/provenance checks.
   Delivery outputs now write lightweight fingerprints so existing files can be
   classified as matching or not matching their current sources, settings, and
   code.
4. Later cleanup or retirement.
   Propose any additional deprecation, archival move, or rename only after the
   naming/role audit lists exact callers, risks, and validation needed.

The naming/role audit is an analysis step first. It may recommend documentation
updates, safe cleanup, architectural/refactoring work, potentially output-affecting
changes, or scientific decisions requiring review. It does not by itself approve
directory moves, script renames, or scientific configuration changes.

Normal completion, Python exceptions, and handled termination clean owned output
locks and workspaces. After SIGKILL, node loss, or storage errors, inspect remaining
jobs before manually recovering stale `.lock` directories or hidden workspaces.
Never remove a lock while its writer could still be active.

## Local regression checks

Use Python 3 with `numpy`, `xarray`, `netCDF4`/`cftime`, `pandas`, `pyarrow`, and
`rasterio`, plus CDO, `ncgen`, and Rscript. CLI GeoTIFF tests additionally use
`gdal_translate` and `gdalinfo` when available.
The tests create only temporary fixtures; no downloads or Slurm submissions occur.
Use Bash 4+ on PATH for full runner coverage. On macOS Bash 3, the submission
harness emulates `mapfile -t` and skips two runners that require lowercase
expansion; these still need the full Bash 4+ check.
The fetch-failure test replaces wget with a local failing stub.

```bash
python3 scripts/tools/test_climatology_monthly_coverage.py
python3 scripts/tools/test_pipeline_safeguards.py
```

The before/after climatology comparison uses the committed worker at `HEAD` as
its reference. Before committing, this compares against the pre-change workers;
after committing, it remains a deterministic numeric smoke test. A full scientific
reference dataset and production toolchain comparison remain release activities.

## Run one model through the scientific pipeline

Download the selected historical and future inputs with the existing fetch runner.
Use the combined ocean/sea-ice manifest when requesting `siconc`. Resolve any
selected manifest checksum conflict before downloading; the validator does not
choose a version for you. `FAIL_ON_ERROR=no` retains exploratory continue/report
behavior but must not be interpreted as a successful complete download.

Set a small explicit model/scenario/variable/window selection first. For example:

```bash
export SMOKE_MODEL=CNRM-ESM2-1
export SMOKE_SCENARIO=ssp585
export SMOKE_VARS='thetao chl'
export SMOKE_WINDOWS='2050-2060'
export SMOKE_MEMBER=auto

# Read-only input and baseline checks after download completion:
STEP=preflight bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh

# Submit monthly preparation. Keep every submitted job ID from the output.
RUN=yes STEP=monthly bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
```

Wait for those jobs to finish. Set `PREVIOUS_JOB_IDS` to their comma-separated IDs,
then run the unit/depth audit and the next stage:

```bash
# Replace the example IDs with all relevant jobs from your run.
export PREVIOUS_JOB_IDS=12345,12346
STEP=verify_jobs bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
RUN=yes STEP=audit bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
RUN=yes STEP=vertical bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
```

For each remaining stage, wait, update `PREVIOUS_JOB_IDS`, and submit separately:

```bash
RUN=yes STEP=climatology bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
RUN=yes STEP=delta bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
RUN=yes STEP=add bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
```

These last commands are separate steps, not a block to execute consecutively.
For mixed 2D/3D selections, the climatology prerequisites include completed monthly
jobs for 2D fields and vertical jobs for 3D fields. `zooc` has no configured trusted
baseline, so its current scientific workflow stops at delta.

The supplied job IDs are operator-selected: the helper verifies their states and
exit codes, not that they correspond to the correct model or files. Direct dataset
runners retain their existing submission interfaces and bypass this coordinator.
`STEP=inputs` performs only the raw-model checks, without requiring baseline roots.
Source unit consistency is not an assertion that every new model is scientifically
compatible; unfamiliar units or depth conventions require review.

## Organize and validate a release

Use the existing product runners after the relevant jobs finish. Organization now
uses `STRICT_INPUTS=yes` by default. `STRICT_INPUTS=no` allows exploratory missing
inputs, but still does not allow a different existing file to count as identical.
`OVERWRITE=yes` explicitly refreshes differing files. The copy comparison reads
both files, so verification adds I/O. The existing parallelism setting is retained.
The configured diagnostic-only `zooc` branch may be absent; existing custom zooc
products remain discoverable. Retired legacy fallback is not used for an unrelated
explicit model selection.

Organization and layer/depth/CSV/Parquet/GeoTIFF delivery default to excluding
`cesm_f09_g16` and `legacy_downscaled_rcp85`, including direct model-subtree inputs
and organizer legacy fallback. New models remain discoverable under `auto`; use
explicit reviewed model lists for releases. Exclusions win over inclusion lists.
These scripts accept a replacement `EXCLUDE_FUTURE_MODELS` list, including an
explicit empty value to clear exclusions. This does not change existing audit or
sample-staging override semantics. Existing historical products are not deleted.
Downstream ensemble exports remain supported; ensemble construction and current-speed
policies remain unchanged.

Prepare an independently reviewed expected-file list for the release: one path
relative to the curated product root per line. Do not derive this list solely from
files that already exist; that would miss absent products.

```bash
PRODUCT_ROOT=/home/SB5/ocean_downscaling_products \
EXPECTED_FILES=/path/to/reviewed_expected_products.txt \
OUT_FILE=/path/to/release_integrity.csv \
COMPUTE_STATS=yes FAIL_ON_ISSUE=yes \
bash scripts/tools/audit_ocean_downscaling_product_integrity.sh
```

The list must match the audit filters. Listed files omitted by filters are reported
as `excluded_expected_product`; absent paths as `missing_product`. Without a list,
the audit checks discovered files and cannot establish complete release coverage.
Run the existing value, unit/depth, and delivery checks as well. Statistical ranges
are evidence to inspect, not automatically approved scientific thresholds.

For GeoTIFF/COG delivery, verify decoded values against their source NetCDF, scaling
and nodata metadata, grid/mask identity, and a representative subset of each
product family. Ensemble uncertainty interpretation, reconstructed depth bounds,
coastal filling, and chlorophyll policies still require scientific review for the
paper; this implementation does not change those methods.

## Record release provenance

Create a JSON object recording the *effective settings used for the actual run*:
models/members, experiments/windows, baseline identities, grids, unit conversions,
anomaly/fill/bounds settings, ensemble exclusions, and export encoding settings.
Do not provide only a desired future configuration. The recorder cannot recover
unrecorded settings from jobs that already ran.

```bash
SETTINGS_FILE=/path/to/effective_settings.json \
OUT_FILE=/path/to/release_provenance.json \
bash scripts/tools/record_ocean_pipeline_release.sh \
  /path/to/source_manifest.csv \
  /path/to/reviewed_expected_products.txt \
  /path/to/release_integrity.csv \
  /path/to/selected_release_products
```

The recorder hashes all supplied files (recursively for directories), includes
working-script hashes and Git status, and never overwrites a previous release
record. It does not certify validation or scientific suitability. Include source
manifests with version/member/checksum information; the record only describes the
files supplied. Hashing a large release should be scheduled with suitable resources.

## Remaining cluster acceptance

Before using the changes for a full release, run a small complete physical and BGC
branch with the cluster's actual CDO/Python versions. Compare values, coordinates,
masks, and metadata against the previous accepted run. Then run the reviewed
expected-product, integrity, value, and export checks on the real release. No
cluster products were inspected or regenerated as part of the local implementation.
