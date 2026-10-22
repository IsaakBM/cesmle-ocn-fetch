# Experimental repository reorganization: first increment

Date: 2026-10-22. Branch: `test/repository-reorganization`.

## Reference and boundaries

The immutable starting point is main commit
`09945d90e60e0f2ede938b671ce8b8033eb881c7`. The original main checkout was
clean. Work takes place in a separate managed Git worktree of the same repository;
main is neither edited nor advanced. No remote push or merge is part of this work.

`tests/fixtures/reorganization_reference.json` records SHA-256 identities for all
147 tracked files at that commit. The regression test requires 143 original files
to remain byte-for-byte identical. Only four original runner files may differ.
This pins scientific workers, numerical routines, exporters, publication and
provenance implementations, manifests, legacy scripts, documentation, and the
existing tests. New files are not part of the original inventory.

The baseline suites were run from an archive of that exact commit in temporary
storage, with Git reads pointed at the existing repository. No pipeline tests
were run against production data. The experimental suites use the separate
worktree. The existing tests' HEAD-based scientific comparisons still read
unchanged numerical scripts; the new runner comparisons always use the pinned
commit rather than a moving HEAD.

## What changed and why

Four product runners contained identical subtree-selection implementations:

- `run_export_ocean_downscaling_products_layers_to_parquet.sh`
- `run_export_ocean_downscaling_products_pelagic_to_parquet.sh`
- `run_export_ocean_downscaling_products_layers_to_geotiff.sh`
- `run_export_ocean_downscaling_products_pelagic_to_geotiff.sh`

Their common selection/filtering and ensemble/scenario expansion now live in
`scripts/lib/product_export_subtrees.sh`. The source blocks were checked for
identity before extraction. The helper documents its input variables and its
`SUBTREES` result. Each runner sources it and calls one selection function after
its original preflight checks.

The runners retain their original configuration blocks, setup checks, status
messages, job names, log paths, sbatch arguments, exported variables, resource
requests, and submission loops. Runner lengths fall from 180/182 to 76/78 lines.
Including the 118-line shared helper, this reduces production code from 724 to
426 lines: 298 lines removed overall.

This deliberately uses the existing `scripts/lib` architecture. It introduces
no configuration framework, new dispatcher, directory renames, or numerical
modules. Atomic-publication consolidation is deferred: it would require changing
exporter internals and their embedded-Python test interfaces, broadening this first
experiment unnecessarily.

## Preserved behavior

- All existing entry-point filenames and executable modes.
- Environment-variable names, defaults, unset/empty semantics, and precedence.
- Model exclusions, baseline inclusion, sorted discovery, ensemble splitting,
  scenario splitting, and fallback to unsplit empty subtrees.
- Worker paths, output paths, temporary paths, job names, Slurm options and exports.
- Every scientific calculation, parameter, worker, exporter, and numerical routine.
- Product provenance schema, logical script identifiers, and freshness behavior.

Release inventories will naturally record different hashes for the edited runners
and include the new library. The release recorder itself is unchanged; those
different source identities accurately describe the experimental code.

## Validation

See `reorganization_validation/` for captured test output and Python dependency
versions. Local environment: macOS arm64, Python 3.14.6, temporary GNU Bash 5.2,
CDO 2.6.3, NetCDF library 4.10.0, GDAL 3.13.1, R 4.6.0.
The Python environment and Bash build were created under temporary storage;
the system shell and repository dependencies were not changed.

| Check | Pinned main | Experimental |
| --- | --- | --- |
| Monthly coverage suite, Bash 5 | 7 passed | 7 passed |
| Safeguard suite, ordinary environment, Bash 5 | 44 passed, 1 failed | 44 passed, same 1 failed |
| Selector fixture alone, `VARS=auto`, Bash 5 | 1 passed | 1 passed |
| Diagnostic full suite with global `VARS=auto` | 44 passed, fetch fixture failed | Same result |
| Runner equivalence and source contracts | Reference | 3 tests passed; 64 runner/case comparisons |
| Shell syntax | Prior review: 101 passed | 102 passed |
| Standalone Python / active R syntax | Unchanged source | Passed |
| Whitespace errors | — | `git diff --check` passed |

The ordinary-environment failure is pre-existing:
`test_delivery_selection_for_roots_and_subtrees` extracts selector functions
but omits the depth-bin tool's `VARS`/`VAR_LIST` initialization. Its baseline
case is therefore rejected when `VARS` is unset. Supplying the tool's actual
default, `VARS=auto`, exercises that fixture without changing test or production
source. Both the failing original invocation and the focused explicit-default
invocation are retained, rather than hiding the baseline failure. A diagnostic
full-suite run with global `VARS=auto` instead makes the fetch fixture fail on
both versions: that acquisition interface interprets `auto` as a literal variable
filter. Therefore the explicit default is appropriate only for the selector
fixture, not a universal test-suite setting. Those diagnostic logs are retained. An initial Bash 3 baseline
run also had this failure and two runner skips; production-supported Bash 5
removes those skips.

The new comparison tests execute real runner control flow and filesystem
discovery against temporary trees. `mkdir` and `sbatch` are intercepted, so no
cluster paths or jobs are created. They compare return codes, stdout, stderr,
and complete ordered sbatch argument lists; only checkout-root locations are
normalized. Sixteen cases per runner cover defaults, model selection, exclusion
precedence and empty overrides, baseline inclusion, split combinations, paths
with spaces, empty model/ensemble trees, missing inputs, explicit Slurm settings,
and failed submissions. Separate assertions compare configuration and submission
source blocks exactly and verify the 143 protected file hashes.

To repeat with Bash 4+ and the listed tools/packages on PATH, from this worktree:

```bash
python3 scripts/tools/test_climatology_monthly_coverage.py
python3 scripts/tools/test_pipeline_safeguards.py
VARS=auto python3 scripts/tools/test_pipeline_safeguards.py \
  SafeguardTests.test_delivery_selection_for_roots_and_subtrees
python3 tests/test_runner_reorganization.py
git diff --check
```

The second command is expected to expose the recorded pre-existing fixture
failure when VARS is unset. The new behavior comparison skips on Bash 3 rather
than claiming unsupported-shell equivalence. Its source-identity assertions
still run. Keep the reference JSON unchanged when extending the experiment;
review any future expansion of the four-file allowlist explicitly.

## Remaining risks and cluster acceptance

Local fixtures and byte-identical scientific source provide strong evidence for
this narrow change; they do not certify full production datasets or a live Slurm
environment. Job scheduling, cluster filesystem permissions, module environments,
and site-specific external callers still need a cluster smoke test. Real NetCDF,
Parquet and raster release products were not regenerated or compared here.

Deploy the new shared library together with the four runners. Copying a runner
alone without its repository-relative library will now fail during sourcing.
The library is used on the submission host; the submitted exporter scripts are
unchanged. Preserve the repository layout during deployment.

No scientific extraction, behavior correction, production execution, merge, or
push is included. The baseline fixture failure remains a separately documented
test-maintenance issue rather than an incidental fix in this refactor.
