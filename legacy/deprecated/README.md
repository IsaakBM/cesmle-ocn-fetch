# Deprecated workflow code

These files are historical references, outside the supported production entry
points. They are preserved for reproducibility; deprecation does not mean their
scientific results are interchangeable with the replacements.

The 2026-09-12 audit moved the following paths from `scripts/` into the same
relative layout under `legacy/deprecated/scripts/`:

| Archived path (relative to `scripts/`) | Production replacement | Reason |
| --- | --- | --- |
| `core/add_anomaly_to_baseline.slurm.sh` | `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | Superseded non-coastal final addition; different coastal and top-layer behavior. |
| `runners/cesm_to_glorys/run_add_anomaly_to_baseline.sh` | Archived coastal-fill CESM reproduction runner in this directory | Launcher for the superseded non-coastal worker. |
| `tools/fill_hindcast_baseline_coastal_gaps.sh` | `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | Superseded patch of an existing `monthly_0p05` baseline. Replacement derives the coastal baseline directly from `monthly_0p25`. |
| `runners/products/run_fill_hindcast_baseline_coastal_gaps.sh` | `scripts/runners/products/run_remap_hindcast_baseline_to_0p05_glorys_coast.sh` | Launcher for the superseded patch step. |
| `bash/z_cesm1_temp.sh` | Retained configurable CESM download scripts under `scripts/bash/` | Hard-coded two-member TEMP download experiment writing to a local Desktop folder; no code callers. |

The non-coastal IPCC/ESGF runner was archived before this audit. Its relative
worker path now resolves to the archived non-coastal worker. Archived runner/tool
pairs retain their relative layout; no forwarding stubs remain in active directories.

`scripts/lib/ipcc_esgf_discovery_obsolete.sh` preserves two helpers removed from
the live library: `ipcc_esgf_discover_monthly_groups` (three-column discovery;
current runners require member-aware discovery) and `ipcc_esgf_label` (unused
label formatter). It is not sourced by production scripts. The unused private
`mtime_file` helper was removed from the wget processor and remains recoverable
in Git history at `571ac91`.


## 2026-09-15 CESM/RCP85 archival

The 2026-09-15 cleanup moved the retained CESM/RCP85 reproduction entry points
out of the active `scripts/` tree after the project decision that CESM/RCP85 is
not part of the current or planned production pipeline. These files are still
tracked for reproducibility and can be inspected or run explicitly from their
legacy paths.

| Archived path | Previous active path | Reason |
| --- | --- | --- |
| `legacy/deprecated/scripts/bash/download_cesmle.sh` | `scripts/bash/download_cesmle.sh` | Historical CESM-LE acquisition helper. |
| `legacy/deprecated/scripts/bash/download_cesmle_list_and_get.sh` | `scripts/bash/download_cesmle_list_and_get.sh` | Historical CESM-LE acquisition helper. |
| `legacy/deprecated/scripts/bash/download_cesmle_list_parallel.sh` | `scripts/bash/download_cesmle_list_parallel.sh` | Historical CESM-LE acquisition helper. |
| `legacy/deprecated/scripts/bash/download_cesmle_list_parallel-hist.sh` | `scripts/bash/download_cesmle_list_parallel-hist.sh` | Historical CESM-LE acquisition helper. |
| `legacy/deprecated/scripts/bash/download_cesmle_list_parallel-proj.sh` | `scripts/bash/download_cesmle_list_parallel-proj.sh` | Historical CESM-LE acquisition helper. |
| `legacy/deprecated/scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh` | `scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh` | Historical CESM/RCP85 final-addition worker. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_temporal_aggregate_regrid.sh` | `scripts/runners/cesm_to_glorys/run_temporal_aggregate_regrid.sh` | Historical CESM/RCP85 reproduction runner. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_vertical_interpolate_to_reference.sh` | `scripts/runners/cesm_to_glorys/run_vertical_interpolate_to_reference.sh` | Historical CESM/RCP85 reproduction runner. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_climatology_window.sh` | `scripts/runners/cesm_to_glorys/run_climatology_window.sh` | Historical CESM/RCP85 reproduction runner. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_delta_from_climatologies.sh` | `scripts/runners/cesm_to_glorys/run_delta_from_climatologies.sh` | Historical CESM/RCP85 reproduction runner. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline_with_coastal_fill.sh` | `scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline_with_coastal_fill.sh` | Historical CESM/RCP85 reproduction runner. |
| `legacy/deprecated/scripts/runners/other_model/.gitkeep` | `scripts/runners/other_model/.gitkeep` | Empty placeholder; archived rather than deleted. |

For historical reproduction, inspect and invoke these archived files explicitly.
Old defaults can reference retired storage layouts or output roots. Review those
settings before running; archived scripts can submit Slurm jobs or write data.
The archived non-coastal workflow must not be silently redirected to the coastal
worker, because that would change the calculation and output layout.

See the [audit report](../../docs/code_lifecycle_audit_2026-09-12.md) for evidence,
retained alternatives, inventory, and validation limits.
