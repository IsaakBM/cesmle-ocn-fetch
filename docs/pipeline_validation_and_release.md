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

## Local regression checks

Use Python 3 with `numpy`, `xarray`, `netCDF4`/`cftime`, plus CDO, `ncgen`, and Rscript.
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
