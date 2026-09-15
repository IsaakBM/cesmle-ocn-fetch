# Script naming and runner-role audit — 2026-09-15

This audit is only about repository script names and `scripts/runners/` directory
names. It does not propose changing data/output directory names such as
`/home/SB5/downscaled`, `/home/SB5/reanalysis/...`, product roots, GeoTIFF roots,
or Parquet roots.

No scripts were renamed, moved, deprecated, or rewritten in this pass.

## Scope

Included:

- all script filenames under `scripts/`
- all directory names directly under `scripts/runners/`
- all runner script filenames nested under `scripts/runners/<name>/`
- source-specific script names outside `scripts/runners/` when the filename
  itself is misleading for the current pipeline

Excluded:

- `/home/SB5` data/output directory names
- product output filenames
- NetCDF/CSV/Parquet/GeoTIFF content
- scientific configuration and processing behavior

## Summary recommendation

Do not do a broad rename. Most current script names are understandable and the
active paths are now protected by the robustness/freshness work. The naming
cleanup is narrow: active runner names stay stable, CESM/RCP85 code is archived
under `legacy/deprecated/`, and the empty `other_model` placeholder is archived
rather than deleted.

Completed decision:

1. Active IPCC/ESGF, GLORYS, BGC hindcast, downscaling, and product runner names
   stay as-is.
2. `scripts/runners/ipcc_esgf_to_hindcast/` stays as-is for this release because
   it is an active wrapper used by callers and runbooks. Its header carries the
   clearer description: IPCC/ESGF to trusted-reference final-addition wrapper.
3. CESM/RCP85 reproduction scripts moved to matching paths under
   `legacy/deprecated/scripts/`.
4. `scripts/runners/other_model/` moved to
   `legacy/deprecated/scripts/runners/other_model/`; no obsolete code was deleted.

## Runner directory names

| Runner directory | Current role | Recommendation | Classification | Risk |
| --- | --- | --- | --- | --- |
| `scripts/runners/glorys/` | GLORYS12v1 reanalysis preparation and climatology runners. | Keep. Name is clear and matches the data source. | Documentation only. | Low. |
| `scripts/runners/global_ocean_biogeochemistry_hindcast/` | BGC hindcast reanalysis preparation and climatology runners. | Keep. Long, but scientifically explicit. | Documentation only. | Low. |
| `scripts/runners/ipcc_esgf/` | IPCC/ESGF model acquisition/preparation/delta runners and smoke-test helper. | Keep. Name is clear. | Documentation only. | Low. |
| `scripts/runners/downscaling/` | Generic anomaly-to-trusted-baseline downscaling launcher. | Keep. It names the action/stage. | Documentation only. | Low. |
| `scripts/runners/ipcc_esgf_to_hindcast/` | Active IPCC/ESGF final-addition wrapper. It routes variables to either GLORYS or BGC hindcast trusted baselines. | Keep for now. Header should say "IPCC/ESGF to trusted-reference final-addition wrapper" because the directory name is narrower than the actual routing. | Documentation now; possible architectural/refactoring later if renamed. | Medium. Called by `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` and runbooks. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/` | CESM/RCP85 historical/reproduction runner family. | Do not use for current production. Archived to legacy/deprecated after historical/reproduction headers were added. | Documentation now; later safe cleanup if archived. | Medium. Not used by current IPCC smoke path, but may have external cluster callers. |
| `scripts/runners/products/` | Product organization, derived products, audits, and delivery exports. | Keep. Name is broad but accurate. | Documentation only. | Low. |
| `legacy/deprecated/scripts/runners/other_model/` | Archived empty placeholder. | None. | Empty placeholder was moved to legacy rather than deleted. | Low. |

## Runner script names

| Runner script | Current role | Recommendation | Classification |
| --- | --- | --- | --- |
| `scripts/runners/glorys/run_temporal_aggregate_regrid.sh` | GLORYS daily/monthly preparation to monthly `parts`. | Keep. | Documentation only. |
| `scripts/runners/glorys/run_climatology_window.sh` | GLORYS climatology windows. | Keep. | Documentation only. |
| `scripts/runners/global_ocean_biogeochemistry_hindcast/run_temporal_aggregate_regrid.sh` | BGC hindcast monthly preparation. | Keep. | Documentation only. |
| `scripts/runners/global_ocean_biogeochemistry_hindcast/run_vertical_interpolate_to_reference.sh` | BGC hindcast vertical matching to reference levels. | Keep. | Documentation only. |
| `scripts/runners/global_ocean_biogeochemistry_hindcast/run_climatology_window.sh` | BGC hindcast climatology windows. | Keep. | Documentation only. |
| `scripts/runners/ipcc_esgf/run_fetch_cmip6_manifest.slurm.sh` | CMIP6 manifest discovery/fetch. | Keep. | Documentation only. |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | One-model staged validation/submission helper. | Keep. | Documentation only. |
| `scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh` | IPCC/ESGF monthly preparation. | Keep. | Documentation only. |
| `scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh` | IPCC/ESGF 3D vertical matching. | Keep. | Documentation only. |
| `scripts/runners/ipcc_esgf/run_climatology_window.sh` | IPCC/ESGF climatology windows. | Keep. | Documentation only. |
| `scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh` | IPCC/ESGF future-minus-baseline deltas. | Keep. | Documentation only. |
| `scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh` | Active final-addition wrapper for IPCC/ESGF deltas. Routes physical variables to GLORYS and BGC variables to hindcast. | Keep filename for now, but update header wording. A later rename would need caller/runbook updates. | Documentation now; possible refactor later. |
| `scripts/runners/downscaling/run_add_anomaly_to_trusted_baseline_with_coastal_fill.sh` | Generic trusted-baseline final-addition launcher. | Keep. Name is accurate. | Documentation only. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_temporal_aggregate_regrid.sh` | CESM/RCP85 historical monthly regridding. | Archived to legacy/deprecated after historical/reproduction headers were added. | Documentation now; later safe cleanup. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_vertical_interpolate_to_reference.sh` | CESM/RCP85 historical vertical matching. | Archived to legacy/deprecated after historical/reproduction headers were added. | Documentation now; later safe cleanup. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_climatology_window.sh` | CESM/RCP85 historical climatology windows. | Archived to legacy/deprecated after historical/reproduction headers were added. | Documentation now; later safe cleanup. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_delta_from_climatologies.sh` | CESM/RCP85 historical member deltas. | Archived to legacy/deprecated after historical/reproduction headers were added. | Documentation now; later safe cleanup. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline_with_coastal_fill.sh` | CESM/RCP85 historical final addition to GLORYS. | Archived to legacy/deprecated after historical/reproduction headers were added. | Documentation now; later safe cleanup. |
| `scripts/runners/products/run_organize_ocean_downscaling_products.sh` | Curated product tree organization. | Keep. | Documentation only. |
| `scripts/runners/products/run_build_ocean_downscaling_ensemble_products.sh` | Ensemble products. | Keep. | Documentation only. |
| `scripts/runners/products/run_derive_current_speed_products.sh` | Derived current-speed products. | Keep. | Documentation only. |
| `scripts/runners/products/run_remap_hindcast_baseline_to_0p05.sh` | Unfilled hindcast baseline remap. | Keep, but keep documented as reproduction/comparison rather than current preferred baseline. | Documentation only. |
| `scripts/runners/products/run_remap_hindcast_baseline_to_0p05_glorys_coast.sh` | Current preferred BGC hindcast baseline remap/fill for GLORYS coast. | Keep. | Documentation only. |
| `scripts/runners/products/run_aggregate_ocean_downscaling_products_fine_layers.sh` | Fine vertical layer products. | Keep. | Documentation only. |
| `scripts/runners/products/run_aggregate_ocean_downscaling_products_pelagic_layers.sh` | Pelagic zone products. | Keep. | Documentation only. |
| `scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh` | Individual-depth products. | Keep. | Documentation only. |
| `scripts/runners/products/run_export_ocean_downscaling_products_bydepth_to_csv.sh` | By-depth CSV export. | Keep. | Documentation only. |
| `scripts/runners/products/run_export_ocean_downscaling_products_depths_to_parquet.sh` | Individual-depth Parquet export. | Keep. | Documentation only. |
| `scripts/runners/products/run_export_ocean_downscaling_products_layers_to_parquet.sh` | Layer Parquet export. | Keep. | Documentation only. |
| `scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_parquet.sh` | Pelagic Parquet export. | Keep. | Documentation only. |
| `scripts/runners/products/run_export_ocean_downscaling_products_layers_to_geotiff.sh` | Layer GeoTIFF export. | Keep. | Documentation only. |
| `scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_geotiff.sh` | Pelagic GeoTIFF export. | Keep. | Documentation only. |
| `scripts/runners/products/run_create_cog_sample_products.sh` | COG sample product creation. | Keep. | Documentation only. |
| `scripts/runners/products/run_stage_ocean_downscaling_sample_products.sh` | Sample product staging. | Keep. | Documentation only. |
| `scripts/runners/products/run_audit_ocean_downscaling_product_integrity.sh` | Product integrity audit. | Keep. | Documentation only. |
| `scripts/runners/products/run_audit_ocean_downscaling_product_values.sh` | Product value audit. | Keep. | Documentation only. |

## Non-runner script filenames

| Script group | Naming assessment | Recommendation | Classification |
| --- | --- | --- | --- |
| `scripts/core/temporal_aggregate_regrid.slurm.sh`, `vertical_interpolate_to_reference.slurm.sh`, `climatology_window_from_monthly_files.slurm.sh`, `climatology_window_from_timeseries.slurm.sh`, `delta_from_climatologies.slurm.sh`, `add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | Generic worker names are accurate. | Keep. | Documentation only. |
| `legacy/deprecated/scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh` | Source-specific CESM worker; no longer active/planned production. | Archived to legacy/deprecated with CESM runners after historical/reproduction headers were added. | Documentation now; later safe cleanup. |
| `scripts/tools/*.sh` product/export/audit tools | Names generally match their action and product family. | Keep. Do not rename before freshness/provenance. | Documentation only. |
| `scripts/tools/audit_downscaled_products.sh` | Name is broad but acceptable; it audits downscaled outputs. | Keep. | Documentation only. |
| `scripts/R/*.R` and `scripts/lib/ipcc_esgf_discovery.sh` | Names are specific and acceptable. | Keep. | Documentation only. |
| `scripts/bash/download_GLORYS_parallel.sh`, `bgc_monthly_download.slurm.sh`, `process_esgf_wget_scripts.sh` | Acquisition/processing names are acceptable. | Keep. | Documentation only. |
| `legacy/deprecated/scripts/bash/download_cesmle*.sh` | CESM-LE acquisition scripts; no longer active/planned production. | Archived to legacy/deprecated after historical/reproduction headers were added. | Documentation now; later safe cleanup. |
| `scripts/bash/archive_sb5_legacy_storage_roots.sh`, `assess_sb5_storage_migration.sh`, `prepare_sb5_storage_layout.sh` | Storage utility names are acceptable. | Keep. | Documentation only. |
| `scripts/tools/test_climatology_monthly_coverage.py`, `test_pipeline_safeguards.py` | Test names are acceptable. | Keep. | Documentation only. |

## Final rename/archive decision table

This is the decision table for script names and `scripts/runners/` names. It does
not apply to output directory names or product filenames.

| Current/archived name | Decision | If changed later | Why | Required approval level |
| --- | --- | --- | --- | --- |
| `scripts/runners/glorys/` | Keep. | None. | Clear source-specific reanalysis runner name. | No approval needed for keeping. |
| `scripts/runners/global_ocean_biogeochemistry_hindcast/` | Keep. | None. | Long but explicit; matches the BGC hindcast source. | No approval needed for keeping. |
| `scripts/runners/ipcc_esgf/` | Keep. | None. | Clear acquisition/preparation/delta stage for IPCC/ESGF models. | No approval needed for keeping. |
| `scripts/runners/downscaling/` | Keep. | None. | Names the stage/action, not an output root. | No approval needed for keeping. |
| `scripts/runners/products/` | Keep. | None. | Clear home for final products, derived products, exports, and audits. | No approval needed for keeping. |
| `scripts/runners/ipcc_esgf_to_hindcast/` | Keep for this release. | Optional later rename to `ipcc_esgf_to_trusted_reference/` only if all callers and runbooks are changed together. | Current name is slightly narrow because variables route to GLORYS or BGC hindcast trusted baselines, but it is active and already referenced. | Architectural/refactoring approval if renamed. |
| `scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh` | Keep for this release. | Optional later rename together with the directory. | Active final-addition wrapper; renaming alone would add breakage risk without changing science. | Architectural/refactoring approval if renamed. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/` | Archived to legacy/deprecated after approval. | None. | CESM/RCP85 is no longer part of current or planned production. | Safe/non-scientific cleanup completed after approval. |
| `legacy/deprecated/scripts/runners/cesm_to_glorys/*.sh` | Archived with the directory after approval. | None. | These are historical/reproduction launchers. | Safe/non-scientific cleanup completed after approval. |
| `legacy/deprecated/scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh` | Archived with CESM scripts after approval. | None. | CESM-specific worker is no longer active production. | Safe/non-scientific cleanup completed after approval. |
| `legacy/deprecated/scripts/bash/download_cesmle*.sh` | Archived with CESM scripts after approval. | None. | CESM-LE acquisition scripts are no longer active production. | Safe/non-scientific cleanup completed after approval. |
| `legacy/deprecated/scripts/runners/other_model/` | Archived to legacy/deprecated after approval. | Moved placeholder directory; never deleted. | Empty placeholder with only `.gitkeep`; not part of the current pipeline. | Safe/non-scientific cleanup completed after approval. |
| Generic core workers in `scripts/core/` | Keep. | None. | Names describe reusable operations. | No approval needed for keeping. |
| Product/export/audit tools in `scripts/tools/` | Keep. | None. | Names match actions and are used by active product runners. | No approval needed for keeping. |
| IPCC/ESGF R discovery/fetch scripts in `scripts/R/` and `scripts/lib/` | Keep. | None. | Names are source-specific and accurate. | No approval needed for keeping. |
| GLORYS/BGC/ESGF acquisition helpers in `scripts/bash/` | Keep, except CESM-LE helpers above. | None. | Names describe data acquisition or storage-layout utilities. | No approval needed for keeping. |

## Header clarification pass

Completed as comment-only cleanup:

1. CESM-specific scripts carry a historical/reproduction lifecycle marker and say
   they are not part of the current active or planned production pipeline.
2. `scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh`
   carries the active trusted-reference final-addition wrapper description while
   keeping the filename unchanged.

No active script or active `scripts/runners/` directory rename is recommended for
this release. The approved CESM archival pass moved only obsolete CESM paths and
the empty `other_model` placeholder to `legacy/deprecated/`.
