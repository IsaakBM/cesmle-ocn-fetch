# Code lifecycle audit — 2026-09-12

Baseline commit: `571ac91` (`Default legacy root archive to no symlinks`).

The audit retires five scripts from active directories and removes three unused
helpers from live code. The production coastal-fill pipeline remains in place.
Archived code is retained under `legacy/deprecated/`; cluster data and jobs were
not touched.

## Coverage and evidence

- Inventoried all 101 tracked shell/R scripts: 79 active, 18 previously archived,
  and four generated ESGF download scripts. Screened all 298 named Bash, R, and
  embedded Python function definitions in the original active scripts.
- Examined repository references, runner-to-worker paths, dynamic Bash exports,
  README/runbook guidance, and Git history. The complete per-file and per-function
  record is in the [inventory](code_lifecycle_inventory_2026-09-12.md).
- Searched locally available project session records, including archived sessions,
  and read the relevant historical decisions. These are historical evidence, not
  new instructions or current cluster telemetry. Chat records outside the local
  history and connected task listing cannot be assumed complete.
- The June 30 task `019f1aad-6366-7a61-a6c1-5c4fa358baaa` explicitly identified
  the four workflow scripts below as retirement candidates, initially pending
  validation. Later in that task, the replacement GLORYS-coast baseline was
  reported complete, with all jobs completed and the expected coastal-cell gains
  across variables. Commits `359552d` and `842a1ce` record the candidate marking
  and replacement implementation.
- The July 26 ensemble discussion (`019fa1eb-3029-7a33-9df9-bb2c7d3ca055`)
  excludes obsolete CESM/RCP85 products from current ensembles and sample
  delivery. This does not establish that all CESM acquisition/preprocessing
  utilities are unused for reproduction.
- The task “Plan data storage migration”
  (`01a06928-bf7b-7270-bd53-d396837c473e`) records successful `thetao` and `chl`
  preflights after migration and the preference for canonical visible paths.
  The subsequent viewer issue was identified by the user as belonging to another
  repository. This audit does not infer the present state of cluster symlinks.

## Retirement decisions

| Original active path | Decision and evidence |
| --- | --- |
| `scripts/tools/fill_hindcast_baseline_coastal_gaps.sh` | Archive. Patch of an already remapped `0p05` baseline; replaced by direct `0p25 -> 0p05_glorys_coast` remap/fill, with historical validation evidence. Only the corresponding old runner references it. |
| `scripts/runners/products/run_fill_hindcast_baseline_coastal_gaps.sh` | Archive with its worker. No other script references this standalone superseded launcher. |
| `scripts/core/add_anomaly_to_baseline.slurm.sh` | Archive. README identifies coastal fill as production; this is the older non-coastal calculation. Its only script consumers are the CESM runner archived here and the already archived IPCC runner. |
| `scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline.sh` | Archive with its worker. Historical candidate; supported CESM coastal-fill runner remains. |
| `scripts/bash/z_cesm1_temp.sh` | Archive. Hard-coded two-member TEMP download experiment writing to `$HOME/Desktop/z_esmLE_test`; no script consumers. Configurable CESM download alternatives remain available. |

The archived files retain their relative directory layout. Both non-coastal
runner paths resolve to the archived worker, and the archived fill runner still
resolves to its tool. The README points production users to the supported paths;
there are no silent forwarding wrappers that substitute a different calculation.
Historical scripts retain their operational defaults and require review before
explicit reproduction runs. See [archive guidance](../legacy/deprecated/README.md).

| Function removed from live code | Original file | Evidence / recovery |
| --- | --- | --- |
| `mtime_file` | `scripts/bash/process_esgf_wget_scripts.sh` | No caller or export; the processor exports `log`, `checksum_file`, and `download_one`. Recoverable in baseline Git history. |
| `ipcc_esgf_discover_monthly_groups` | `scripts/lib/ipcc_esgf_discovery.sh` | No callers. Old three-column layout discovery is superseded by member-aware `ipcc_esgf_discover_monthly_groups_any_layout`; preserved in the archive helper file. |
| `ipcc_esgf_label` | `scripts/lib/ipcc_esgf_discovery.sh` | No callers; preserved in the archive helper file. |

## Retained code and unresolved usage

- **Current compatibility wrapper:**
  `scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh`
  is production code despite its compatibility header. It discovers groups,
  routes physical/BGC baselines, handles variable policies, and is called by the
  smoke-test workflow. Removing it would break the current pipeline.
- **Original unfilled hindcast remap:** retain the tool and runner. They produce
  a distinct unfilled baseline, useful for reproduction and comparison. Replace
  stale “pending replacement” comments with an explicit reproduction designation.
- **CESM preprocessing and coastal addition:** retain the runners, acquisition
  alternatives, time-series climatology worker, and member coastal-fill worker.
  Exclusion from CMIP6 delivery is not proof that this reproduction chain is unused.
- **Mixed storage-layout discovery:** retain member-aware and older-layout support
  inside the live discovery library. Runtime filenames and directory layouts are
  discovered dynamically; migration history does not prove all old layouts absent.
- **Audits and migration utilities:** retain. Standalone diagnostics and dry-run
  tools are intentionally invoked manually, often with no repository caller.
- **CSV, Parquet, GeoTIFF, depth, layer, pelagic, and COG tools:** retain. These
  serve different delivery products, and the project history records their use.
  COG sample delivery does not replace every exporter or full product family.
- **Previously archived scripts and generated ESGF inputs:** preserve as historical
  reference/download input. Do not treat generated functions as active library APIs.

No additional named functions met the zero-reference criterion. References are
lexical evidence and may include comments, exports, and callbacks; duplicate helper
names are not sufficient reason to refactor otherwise independent job scripts.
Further retirement of these retained entry points needs evidence about external
launch commands or explicit discontinuation of the corresponding product family.

## Validation and limits

- `bash -n`: all 99 shell files after the archive, including the new historical
  helper file, archived scripts, and generated ESGF inputs.
- Python AST parsing: all 29 detected Python heredoc blocks.
- R parsing: all three scripts under `scripts/R/`.
- Eight before/after discovery fixtures matched in exit status, stdout, and
  stderr: mixed member/legacy layouts, missing roots/stages, stage resolution,
  download discovery, valid filenames, and invalid filenames. Explicit expected
  groups also confirmed that two members remain distinct in the older layout.
- All 43 literal `SCRIPT_DIR`-relative shell/R dependency paths resolve, including
  the archived runner/worker pairs.
- `git diff --check` passes; retired helpers have no remaining live references.

These checks validate local syntax, dependency paths, and the affected discovery
behavior. They do not establish full numerical equivalence or current usage on
the cluster. Slurm submissions, CDO/GDAL processing, live datasets, and external
scripts were not exercised. No production computation was intentionally changed.
Existing external commands that use a retired path must use the documented
replacement or explicitly invoke the archived implementation for reproduction.
