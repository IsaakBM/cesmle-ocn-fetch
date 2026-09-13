# Script and function inventory — 2026-09-12

Baseline: `571ac91`. This is a static audit snapshot, not runtime usage telemetry.
See the [decision report](code_lifecycle_audit_2026-09-12.md).

## Scripts

All 101 tracked `.sh` / `.R` files at the baseline are included: 79 under
`scripts/`, 18 already under `legacy/`, and four generated ESGF download scripts.
Reference counts are other script files containing the basename, including comments;
they are discovery hints, not verified calls. Zero is expected for manual entry points.

| Baseline path | Decision | Other script text references |
| --- | --- | ---: |
| [data/ipcc_esgf_wget/wget_script_2026-4-10_13-53-10.sh](../data/ipcc_esgf_wget/wget_script_2026-4-10_13-53-10.sh) | Retained generated download input | 0 |
| [data/ipcc_esgf_wget/wget_script_2026-4-10_13-53-17.sh](../data/ipcc_esgf_wget/wget_script_2026-4-10_13-53-17.sh) | Retained generated download input | 0 |
| [data/ipcc_esgf_wget/wget_script_2026-4-10_13-53-3.sh](../data/ipcc_esgf_wget/wget_script_2026-4-10_13-53-3.sh) | Retained generated download input | 0 |
| [data/ipcc_esgf_wget/wget_script_2026-4-10_14-11-21.sh](../data/ipcc_esgf_wget/wget_script_2026-4-10_14-11-21.sh) | Retained generated download input | 0 |
| [legacy/deprecated/scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline.sh](../legacy/deprecated/scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline.sh) | Previously archived | 0 |
| [legacy/scripts/slurm/cesm_add_to_glorys_downscale.slurm.sh](../legacy/scripts/slurm/cesm_add_to_glorys_downscale.slurm.sh) | Previously archived | 1 |
| [legacy/scripts/slurm/cesm_member_deltas_0p05.slurm.sh](../legacy/scripts/slurm/cesm_member_deltas_0p05.slurm.sh) | Previously archived | 1 |
| [legacy/scripts/slurm/cesm_vertical_regrid.slurm.sh](../legacy/scripts/slurm/cesm_vertical_regrid.slurm.sh) | Previously archived | 1 |
| [legacy/scripts/slurm/cesm_window_climatologies.slurm.sh](../legacy/scripts/slurm/cesm_window_climatologies.slurm.sh) | Previously archived | 1 |
| [legacy/scripts/slurm/glorys_monthly_0p05.slurm.sh](../legacy/scripts/slurm/glorys_monthly_0p05.slurm.sh) | Previously archived | 1 |
| [legacy/scripts/slurm/glorys_window_climatology.slurm.sh](../legacy/scripts/slurm/glorys_window_climatology.slurm.sh) | Previously archived | 1 |
| [legacy/scripts/slurm/regrid_cesm_pop_1deg.slurm.sh](../legacy/scripts/slurm/regrid_cesm_pop_1deg.slurm.sh) | Previously archived | 3 |
| [legacy/scripts/slurm/regrid_cesm_pop_1deg_homeout.slurm.sh](../legacy/scripts/slurm/regrid_cesm_pop_1deg_homeout.slurm.sh) | Previously archived | 1 |
| [legacy/scripts/slurm/run_cesm_add_to_glorys_downscale.sh](../legacy/scripts/slurm/run_cesm_add_to_glorys_downscale.sh) | Previously archived | 0 |
| [legacy/scripts/slurm/run_cesm_member_deltas_0p05.sh](../legacy/scripts/slurm/run_cesm_member_deltas_0p05.sh) | Previously archived | 0 |
| [legacy/scripts/slurm/run_cesm_vertical_regrid.sh](../legacy/scripts/slurm/run_cesm_vertical_regrid.sh) | Previously archived | 0 |
| [legacy/scripts/slurm/run_cesm_window_climatologies.sh](../legacy/scripts/slurm/run_cesm_window_climatologies.sh) | Previously archived | 0 |
| [legacy/scripts/slurm/run_glorys_monthly_0p05.sh](../legacy/scripts/slurm/run_glorys_monthly_0p05.sh) | Previously archived | 0 |
| [legacy/scripts/slurm/run_glorys_window_climatology.sh](../legacy/scripts/slurm/run_glorys_window_climatology.sh) | Previously archived | 0 |
| [legacy/scripts/slurm/run_regrid.sh](../legacy/scripts/slurm/run_regrid.sh) | Previously archived | 0 |
| [legacy/scripts/slurm/run_regrid_deps.sh](../legacy/scripts/slurm/run_regrid_deps.sh) | Previously archived | 0 |
| [legacy/scripts/slurm/run_regrid_homeout.sh](../legacy/scripts/slurm/run_regrid_homeout.sh) | Previously archived | 0 |
| [scripts/R/audit_pipeline_path_assumptions.R](../scripts/R/audit_pipeline_path_assumptions.R) | Retained audit / storage utility | 0 |
| [scripts/R/discover_ipcc_esgf_nci_cmip6.R](../scripts/R/discover_ipcc_esgf_nci_cmip6.R) | Retained pipeline / delivery | 0 |
| [scripts/R/fetch_ipcc_esgf_cmip6_manifest.R](../scripts/R/fetch_ipcc_esgf_cmip6_manifest.R) | Retained pipeline / delivery | 1 |
| [scripts/bash/archive_sb5_legacy_storage_roots.sh](../scripts/bash/archive_sb5_legacy_storage_roots.sh) | Retained audit / storage utility | 0 |
| [scripts/bash/assess_sb5_storage_migration.sh](../scripts/bash/assess_sb5_storage_migration.sh) | Retained audit / storage utility | 0 |
| [scripts/bash/bgc_monthly_download.slurm.sh](../scripts/bash/bgc_monthly_download.slurm.sh) | Retained acquisition utility | 0 |
| [scripts/bash/download_GLORYS_parallel.sh](../scripts/bash/download_GLORYS_parallel.sh) | Retained acquisition utility | 0 |
| [scripts/bash/download_cesmle.sh](../scripts/bash/download_cesmle.sh) | Retained CESM reproduction | 0 |
| [scripts/bash/download_cesmle_list_and_get.sh](../scripts/bash/download_cesmle_list_and_get.sh) | Retained CESM reproduction | 0 |
| [scripts/bash/download_cesmle_list_parallel-hist.sh](../scripts/bash/download_cesmle_list_parallel-hist.sh) | Retained CESM reproduction | 0 |
| [scripts/bash/download_cesmle_list_parallel-proj.sh](../scripts/bash/download_cesmle_list_parallel-proj.sh) | Retained CESM reproduction | 0 |
| [scripts/bash/download_cesmle_list_parallel.sh](../scripts/bash/download_cesmle_list_parallel.sh) | Retained CESM reproduction | 0 |
| [scripts/bash/prepare_sb5_storage_layout.sh](../scripts/bash/prepare_sb5_storage_layout.sh) | Retained audit / storage utility | 0 |
| [scripts/bash/process_esgf_wget_scripts.sh](../scripts/bash/process_esgf_wget_scripts.sh) | Retained acquisition utility | 0 |
| [scripts/bash/z_cesm1_temp.sh](../legacy/deprecated/scripts/bash/z_cesm1_temp.sh) | Archived in this audit | 0 |
| [scripts/core/add_anomaly_to_baseline.slurm.sh](../legacy/deprecated/scripts/core/add_anomaly_to_baseline.slurm.sh) | Archived in this audit | 2 |
| [scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh](../scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh) | Retained pipeline / delivery | 3 |
| [scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh](../scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh) | Retained CESM reproduction | 1 |
| [scripts/core/climatology_window_from_monthly_files.slurm.sh](../scripts/core/climatology_window_from_monthly_files.slurm.sh) | Retained pipeline / delivery | 2 |
| [scripts/core/climatology_window_from_timeseries.slurm.sh](../scripts/core/climatology_window_from_timeseries.slurm.sh) | Retained pipeline / delivery | 2 |
| [scripts/core/delta_from_climatologies.slurm.sh](../scripts/core/delta_from_climatologies.slurm.sh) | Retained pipeline / delivery | 2 |
| [scripts/core/temporal_aggregate_regrid.slurm.sh](../scripts/core/temporal_aggregate_regrid.slurm.sh) | Retained pipeline / delivery | 4 |
| [scripts/core/vertical_interpolate_to_reference.slurm.sh](../scripts/core/vertical_interpolate_to_reference.slurm.sh) | Retained pipeline / delivery | 3 |
| [scripts/lib/ipcc_esgf_discovery.sh](../scripts/lib/ipcc_esgf_discovery.sh) | Retained pipeline / delivery | 5 |
| [scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline.sh](../legacy/deprecated/scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline.sh) | Archived in this audit | 0 |
| [scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline_with_coastal_fill.sh](../scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline_with_coastal_fill.sh) | Retained CESM reproduction | 1 |
| [scripts/runners/cesm_to_glorys/run_climatology_window.sh](../scripts/runners/cesm_to_glorys/run_climatology_window.sh) | Retained CESM reproduction | 1 |
| [scripts/runners/cesm_to_glorys/run_delta_from_climatologies.sh](../scripts/runners/cesm_to_glorys/run_delta_from_climatologies.sh) | Retained CESM reproduction | 1 |
| [scripts/runners/cesm_to_glorys/run_temporal_aggregate_regrid.sh](../scripts/runners/cesm_to_glorys/run_temporal_aggregate_regrid.sh) | Retained CESM reproduction | 1 |
| [scripts/runners/cesm_to_glorys/run_vertical_interpolate_to_reference.sh](../scripts/runners/cesm_to_glorys/run_vertical_interpolate_to_reference.sh) | Retained CESM reproduction | 1 |
| [scripts/runners/downscaling/run_add_anomaly_to_trusted_baseline_with_coastal_fill.sh](../scripts/runners/downscaling/run_add_anomaly_to_trusted_baseline_with_coastal_fill.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/global_ocean_biogeochemistry_hindcast/run_climatology_window.sh](../scripts/runners/global_ocean_biogeochemistry_hindcast/run_climatology_window.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/global_ocean_biogeochemistry_hindcast/run_temporal_aggregate_regrid.sh](../scripts/runners/global_ocean_biogeochemistry_hindcast/run_temporal_aggregate_regrid.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/global_ocean_biogeochemistry_hindcast/run_vertical_interpolate_to_reference.sh](../scripts/runners/global_ocean_biogeochemistry_hindcast/run_vertical_interpolate_to_reference.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/glorys/run_climatology_window.sh](../scripts/runners/glorys/run_climatology_window.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/glorys/run_temporal_aggregate_regrid.sh](../scripts/runners/glorys/run_temporal_aggregate_regrid.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/ipcc_esgf/run_climatology_window.sh](../scripts/runners/ipcc_esgf/run_climatology_window.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh](../scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/ipcc_esgf/run_fetch_cmip6_manifest.slurm.sh](../scripts/runners/ipcc_esgf/run_fetch_cmip6_manifest.slurm.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh](../scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh](../scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh](../scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh](../scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh) | Retained pipeline / delivery | 1 |
| [scripts/runners/products/run_aggregate_ocean_downscaling_products_fine_layers.sh](../scripts/runners/products/run_aggregate_ocean_downscaling_products_fine_layers.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_aggregate_ocean_downscaling_products_pelagic_layers.sh](../scripts/runners/products/run_aggregate_ocean_downscaling_products_pelagic_layers.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_audit_ocean_downscaling_product_integrity.sh](../scripts/runners/products/run_audit_ocean_downscaling_product_integrity.sh) | Retained audit / storage utility | 0 |
| [scripts/runners/products/run_audit_ocean_downscaling_product_values.sh](../scripts/runners/products/run_audit_ocean_downscaling_product_values.sh) | Retained audit / storage utility | 0 |
| [scripts/runners/products/run_build_ocean_downscaling_ensemble_products.sh](../scripts/runners/products/run_build_ocean_downscaling_ensemble_products.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_create_cog_sample_products.sh](../scripts/runners/products/run_create_cog_sample_products.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_derive_current_speed_products.sh](../scripts/runners/products/run_derive_current_speed_products.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_export_ocean_downscaling_products_bydepth_to_csv.sh](../scripts/runners/products/run_export_ocean_downscaling_products_bydepth_to_csv.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_export_ocean_downscaling_products_depths_to_parquet.sh](../scripts/runners/products/run_export_ocean_downscaling_products_depths_to_parquet.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_export_ocean_downscaling_products_layers_to_geotiff.sh](../scripts/runners/products/run_export_ocean_downscaling_products_layers_to_geotiff.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_export_ocean_downscaling_products_layers_to_parquet.sh](../scripts/runners/products/run_export_ocean_downscaling_products_layers_to_parquet.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_geotiff.sh](../scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_geotiff.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_parquet.sh](../scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_parquet.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_fill_hindcast_baseline_coastal_gaps.sh](../legacy/deprecated/scripts/runners/products/run_fill_hindcast_baseline_coastal_gaps.sh) | Archived in this audit | 0 |
| [scripts/runners/products/run_organize_ocean_downscaling_products.sh](../scripts/runners/products/run_organize_ocean_downscaling_products.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_remap_hindcast_baseline_to_0p05.sh](../scripts/runners/products/run_remap_hindcast_baseline_to_0p05.sh) | Retained unfilled baseline reproduction | 0 |
| [scripts/runners/products/run_remap_hindcast_baseline_to_0p05_glorys_coast.sh](../scripts/runners/products/run_remap_hindcast_baseline_to_0p05_glorys_coast.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh](../scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh) | Retained pipeline / delivery | 0 |
| [scripts/runners/products/run_stage_ocean_downscaling_sample_products.sh](../scripts/runners/products/run_stage_ocean_downscaling_sample_products.sh) | Retained pipeline / delivery | 0 |
| [scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh](../scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh) | Retained pipeline / delivery | 2 |
| [scripts/tools/audit_downscaled_products.sh](../scripts/tools/audit_downscaled_products.sh) | Retained audit / storage utility | 0 |
| [scripts/tools/audit_ocean_downscaling_product_integrity.sh](../scripts/tools/audit_ocean_downscaling_product_integrity.sh) | Retained audit / storage utility | 1 |
| [scripts/tools/audit_ocean_downscaling_product_values.sh](../scripts/tools/audit_ocean_downscaling_product_values.sh) | Retained audit / storage utility | 1 |
| [scripts/tools/audit_units_and_depths.sh](../scripts/tools/audit_units_and_depths.sh) | Retained audit / storage utility | 1 |
| [scripts/tools/build_ocean_downscaling_ensemble_products.sh](../scripts/tools/build_ocean_downscaling_ensemble_products.sh) | Retained pipeline / delivery | 1 |
| [scripts/tools/create_cog_sample_products.sh](../scripts/tools/create_cog_sample_products.sh) | Retained pipeline / delivery | 1 |
| [scripts/tools/derive_current_speed_products.sh](../scripts/tools/derive_current_speed_products.sh) | Retained pipeline / delivery | 1 |
| [scripts/tools/export_ocean_downscaling_products_bydepth_to_csv.sh](../scripts/tools/export_ocean_downscaling_products_bydepth_to_csv.sh) | Retained pipeline / delivery | 1 |
| [scripts/tools/export_ocean_downscaling_products_to_geotiff.sh](../scripts/tools/export_ocean_downscaling_products_to_geotiff.sh) | Retained pipeline / delivery | 3 |
| [scripts/tools/export_ocean_downscaling_products_to_parquet.sh](../scripts/tools/export_ocean_downscaling_products_to_parquet.sh) | Retained pipeline / delivery | 3 |
| [scripts/tools/fill_hindcast_baseline_coastal_gaps.sh](../legacy/deprecated/scripts/tools/fill_hindcast_baseline_coastal_gaps.sh) | Archived in this audit | 1 |
| [scripts/tools/organize_ocean_downscaling_products.sh](../scripts/tools/organize_ocean_downscaling_products.sh) | Retained pipeline / delivery | 1 |
| [scripts/tools/remap_hindcast_baseline_to_0p05.sh](../scripts/tools/remap_hindcast_baseline_to_0p05.sh) | Retained unfilled baseline reproduction | 1 |
| [scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh](../scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh) | Retained pipeline / delivery | 1 |
| [scripts/tools/split_ocean_downscaling_products_by_depth.sh](../scripts/tools/split_ocean_downscaling_products_by_depth.sh) | Retained pipeline / delivery | 1 |
| [scripts/tools/stage_ocean_downscaling_sample_products.sh](../scripts/tools/stage_ocean_downscaling_sample_products.sh) | Retained pipeline / delivery | 1 |

## Function definitions in the original active scripts

All 298 named Bash, R, and Python function definitions detected in active scripts,
including embedded Python and indented definitions. Anonymous functions and generated
download code are outside this function table. Counts below are same-file symbol
occurrences beyond the definition; comments, exports, and callback references count.
Shared library functions also need cross-file inspection. Only the three functions
listed as removed had no other symbol occurrences across the original script inventory.
This is a conservative candidate screen, not a complete semantic call graph.

| Original file | Function | Same-file references | Decision |
| --- | --- | ---: | --- |
| `scripts/R/audit_pipeline_path_assumptions.R` | `env_value` | 2 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `env_value` | 11 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `split_env` | 3 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `query_url` | 1 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `first_value` | 14 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `http_url` | 8 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `parse_time_range` | 1 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `member_key` | 1 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `window_rows_for_experiment` | 1 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `file_overlaps_window` | 1 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `doc_to_row` | 1 | Retained |
| `scripts/R/discover_ipcc_esgf_nci_cmip6.R` | `fetch_file_rows` | 2 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `env_value` | 16 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `split_env` | 4 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `file_time_range` | 1 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `overlaps_window` | 1 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `needed_for_windows` | 1 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `target_path` | 5 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `checksum_file` | 2 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `write_fetch_plan` | 1 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `load_replica_rows` | 1 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `candidate_urls` | 1 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `download_url` | 1 | Retained |
| `scripts/R/fetch_ipcc_esgf_cmip6_manifest.R` | `download_one` | 1 | Retained |
| `scripts/bash/archive_sb5_legacy_storage_roots.sh` | `run_cmd` | 3 | Retained |
| `scripts/bash/archive_sb5_legacy_storage_roots.sh` | `archive_one` | 7 | Retained |
| `scripts/bash/bgc_monthly_download.slurm.sh` | `tidy_nested_if_any` | 2 | Retained |
| `scripts/bash/bgc_monthly_download.slurm.sh` | `fetch_month` | 2 | Retained |
| `scripts/bash/download_GLORYS_parallel.sh` | `tidy_nested_if_any` | 2 | Retained |
| `scripts/bash/download_GLORYS_parallel.sh` | `fetch_month` | 2 | Retained |
| `scripts/bash/download_cesmle_list_and_get.sh` | `list_member_files` | 1 | Retained |
| `scripts/bash/download_cesmle_list_and_get.sh` | `grab_if_needed` | 1 | Retained |
| `scripts/bash/download_cesmle_list_parallel-hist.sh` | `http_ok` | 1 | Retained |
| `scripts/bash/download_cesmle_list_parallel-hist.sh` | `download_one` | 3 | Retained |
| `scripts/bash/download_cesmle_list_parallel-proj.sh` | `http_ok` | 1 | Retained |
| `scripts/bash/download_cesmle_list_parallel-proj.sh` | `download_one` | 3 | Retained |
| `scripts/bash/process_esgf_wget_scripts.sh` | `usage` | 4 | Retained |
| `scripts/bash/process_esgf_wget_scripts.sh` | `log` | 10 | Retained |
| `scripts/bash/process_esgf_wget_scripts.sh` | `require_commands` | 1 | Retained |
| `scripts/bash/process_esgf_wget_scripts.sh` | `checksum_file` | 3 | Retained |
| `scripts/bash/process_esgf_wget_scripts.sh` | `mtime_file` | 0 | Removed from live code |
| `scripts/bash/process_esgf_wget_scripts.sh` | `append_script_entries` | 1 | Retained |
| `scripts/bash/process_esgf_wget_scripts.sh` | `collect_inputs` | 1 | Retained |
| `scripts/bash/process_esgf_wget_scripts.sh` | `download_one` | 2 | Retained |
| `scripts/core/add_anomaly_to_baseline.slurm.sh` | `pick_main_var` | 1 | Archived with superseded script |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `detect_gridtype` | 1 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `resolve_anomaly_method` | 1 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `pick_main_var` | 2 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `parse_output_bounds` | 1 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `parse_anomaly_scale` | 1 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `set_climatology_time` | 1 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `infer_xy_dims` | 1 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `align_to_base_dims` | 1 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `build_fill_geometry` | 1 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `fill_slice_nearest` | 2 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `fill_slice_distance_weighted` | 2 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `fill_slice_require_complete` | 1 | Retained |
| `scripts/core/add_anomaly_to_baseline_with_coastal_fill.slurm.sh` | `finite_wet_neighbors` | 2 | Retained |
| `scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh` | `glorys_var_for_cesm_var` | 1 | Retained |
| `scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh` | `realization_for_member_tag` | 1 | Retained |
| `scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh` | `process_one_anomaly_file` | 1 | Retained |
| `scripts/core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh` | `process_window` | 2 | Retained |
| `scripts/core/climatology_window_from_monthly_files.slurm.sh` | `pick_main_var` | 1 | Retained |
| `scripts/core/delta_from_climatologies.slurm.sh` | `pick_main_var` | 2 | Retained |
| `scripts/core/temporal_aggregate_regrid.slurm.sh` | `detect_gridtype` | 2 | Retained |
| `scripts/core/temporal_aggregate_regrid.slurm.sh` | `resolve_method` | 3 | Retained |
| `scripts/core/temporal_aggregate_regrid.slurm.sh` | `process_month` | 2 | Retained |
| `scripts/core/temporal_aggregate_regrid.slurm.sh` | `process_timeseries_file` | 2 | Retained |
| `scripts/core/vertical_interpolate_to_reference.slurm.sh` | `process_one_file` | 2 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_parse_filename` | 2 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_discover_download_groups` | 0 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_discover_monthly_groups` | 0 | Removed from live code |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_discover_monthly_groups_with_members` | 1 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_discover_monthly_groups_any_layout` | 0 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_monthly_stage_dir_for_group` | 0 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_monthly_var_dir_for_group` | 0 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_download_dir_for_group` | 0 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_members_from_files` | 2 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_members_from_product_files` | 1 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_resolve_member` | 0 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_resolve_product_member` | 0 | Retained |
| `scripts/lib/ipcc_esgf_discovery.sh` | `ipcc_esgf_label` | 0 | Removed from live code |
| `scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline.sh` | `glorys_var_for_cesm_var` | 1 | Archived with superseded script |
| `scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline.sh` | `member_prefix` | 2 | Archived with superseded script |
| `scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline.sh` | `delta_dir_for_cesm_var` | 2 | Archived with superseded script |
| `scripts/runners/cesm_to_glorys/run_add_anomaly_to_baseline.sh` | `delta_file_for_member_window` | 1 | Archived with superseded script |
| `scripts/runners/cesm_to_glorys/run_climatology_window.sh` | `member_prefix` | 1 | Retained |
| `scripts/runners/cesm_to_glorys/run_delta_from_climatologies.sh` | `member_prefix` | 1 | Retained |
| `scripts/runners/downscaling/run_add_anomaly_to_trusted_baseline_with_coastal_fill.sh` | `render_template` | 4 | Retained |
| `scripts/runners/downscaling/run_add_anomaly_to_trusted_baseline_with_coastal_fill.sh` | `anomaly_mode_for_var` | 1 | Retained |
| `scripts/runners/glorys/run_climatology_window.sh` | `make_sbatch_extra_args` | 1 | Retained |
| `scripts/runners/glorys/run_temporal_aggregate_regrid.sh` | `make_sbatch_extra_args` | 1 | Retained |
| `scripts/runners/ipcc_esgf/run_climatology_window.sh` | `contains_filter_value` | 6 | Retained |
| `scripts/runners/ipcc_esgf/run_climatology_window.sh` | `make_sbatch_extra_args` | 1 | Retained |
| `scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh` | `contains_filter_value` | 3 | Retained |
| `scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh` | `make_sbatch_extra_args` | 1 | Retained |
| `scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh` | `delta_mode_for_var` | 1 | Retained |
| `scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh` | `spec_value_for_var` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh` | `target_family_for_var` | 1 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `run_or_print` | 6 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `contains_word` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `require_dir` | 5 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `require_file` | 4 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `sample_file_count` | 4 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `find_first_dir` | 5 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `preflight_step` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `monthly_step` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `audit_step` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `vertical_step` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `climatology_step` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `delta_step` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `add_step` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh` | `print_plan` | 1 | Retained |
| `scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh` | `contains_filter_value` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh` | `make_sbatch_extra_args` | 1 | Retained |
| `scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh` | `contains_filter_value` | 2 | Retained |
| `scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh` | `make_sbatch_extra_args` | 1 | Retained |
| `scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh` | `uses_coastal_mask` | 1 | Retained |
| `scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh` | `contains_word` | 5 | Retained |
| `scripts/runners/products/run_aggregate_ocean_downscaling_products_fine_layers.sh` | `contains_word` | 2 | Retained |
| `scripts/runners/products/run_aggregate_ocean_downscaling_products_fine_layers.sh` | `include_subtree` | 1 | Retained |
| `scripts/runners/products/run_aggregate_ocean_downscaling_products_pelagic_layers.sh` | `contains_word` | 2 | Retained |
| `scripts/runners/products/run_aggregate_ocean_downscaling_products_pelagic_layers.sh` | `include_subtree` | 1 | Retained |
| `scripts/runners/products/run_create_cog_sample_products.sh` | `submit_job` | 4 | Retained |
| `scripts/runners/products/run_create_cog_sample_products.sh` | `collect_subtrees` | 1 | Retained |
| `scripts/runners/products/run_derive_current_speed_products.sh` | `submit_job` | 4 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_depths_to_parquet.sh` | `contains_word` | 2 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_depths_to_parquet.sh` | `include_subtree` | 1 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_layers_to_geotiff.sh` | `contains_word` | 2 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_layers_to_geotiff.sh` | `include_subtree` | 1 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_layers_to_parquet.sh` | `contains_word` | 2 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_layers_to_parquet.sh` | `include_subtree` | 1 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_geotiff.sh` | `contains_word` | 2 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_geotiff.sh` | `include_subtree` | 1 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_parquet.sh` | `contains_word` | 2 | Retained |
| `scripts/runners/products/run_export_ocean_downscaling_products_pelagic_to_parquet.sh` | `include_subtree` | 1 | Retained |
| `scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh` | `contains_word` | 2 | Retained |
| `scripts/runners/products/run_split_ocean_downscaling_products_by_depth.sh` | `include_subtree` | 1 | Retained |
| `scripts/runners/products/run_stage_ocean_downscaling_sample_products.sh` | `contains_word` | 1 | Retained |
| `scripts/runners/products/run_stage_ocean_downscaling_sample_products.sh` | `include_product_family` | 3 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `contains_word` | 2 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `include_relative_path` | 1 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `process_one_file` | 2 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `is_ignored_var` | 2 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `choose_zdim` | 1 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `choose_main_var` | 1 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `preserve_referenced_auxiliary_vars` | 1 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `detect_bounds` | 1 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `reconstruct_bounds` | 1 | Retained |
| `scripts/tools/aggregate_ocean_downscaling_products_by_depth_bins.sh` | `normalize_bounds` | 1 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `contains_word` | 7 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `csv_escape` | 1 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `csv_row` | 2 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `target_family_for_var` | 4 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `expected_resolution_for_var` | 1 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `baseline_file_for_product` | 1 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `fallback_baseline_file_for_product` | 1 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `get_attr` | 3 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `grid_summary` | 2 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `gridtypes_compatible` | 1 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `level_count` | 1 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `stat_values_to_single` | 1 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `cdo_stat` | 3 | Retained |
| `scripts/tools/audit_downscaled_products.sh` | `status_from_checks` | 1 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_integrity.sh` | `contains_token` | 1 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_integrity.sh` | `token_text_for_record` | 1 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_integrity.sh` | `pick_main_var` | 1 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_integrity.sh` | `numeric_years` | 2 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_integrity.sh` | `stat_text` | 3 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_integrity.sh` | `audit_one` | 2 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_values.sh` | `contains_word` | 2 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_values.sh` | `csv_quote` | 8 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_values.sh` | `passes_filter` | 5 | Retained |
| `scripts/tools/audit_ocean_downscaling_product_values.sh` | `cdo_stat` | 4 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `contains_word` | 2 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `csv_escape` | 1 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `csv_row` | 2 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `normalize_units` | 5 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `get_attr` | 4 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `has_var` | 1 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `pick_data_var` | 2 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `pick_zdim` | 2 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `levels_min_max` | 2 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `field_min_max` | 2 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `baseline_target_for_var` | 1 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `baseline_file_for_var` | 1 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `suggest_z_scale_and_note` | 1 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `suggest_var_scale_and_note` | 1 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `suggest_add_stage_scale_bounds_and_note` | 1 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `status_from_notes` | 1 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `list_values_or_dirs` | 4 | Retained |
| `scripts/tools/audit_units_and_depths.sh` | `first_stage_file` | 1 | Retained |
| `scripts/tools/build_ocean_downscaling_ensemble_products.sh` | `contains_word` | 3 | Retained |
| `scripts/tools/build_ocean_downscaling_ensemble_products.sh` | `variable_specific_excluded_models` | 3 | Retained |
| `scripts/tools/build_ocean_downscaling_ensemble_products.sh` | `years_from_values` | 2 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `has_cog_driver` | 2 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `compression_supported` | 1 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `choose_compression` | 1 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `include_source_file` | 2 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `collect_files` | 1 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `validate_one_cog` | 3 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `convert_one_file` | 2 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `write_manifests` | 1 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `read_manifest` | 1 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `row_points_to_kept_tree` | 1 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `update_row` | 1 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `write_manifest` | 1 | Retained |
| `scripts/tools/create_cog_sample_products.sh` | `validate_tree_and_manifests` | 1 | Retained |
| `scripts/tools/derive_current_speed_products.sh` | `contains_word` | 3 | Retained |
| `scripts/tools/derive_current_speed_products.sh` | `make_current_speed` | 2 | Retained |
| `scripts/tools/derive_current_speed_products.sh` | `current_speed_basename` | 2 | Retained |
| `scripts/tools/derive_current_speed_products.sh` | `derive_baseline` | 2 | Retained |
| `scripts/tools/derive_current_speed_products.sh` | `derive_future` | 2 | Retained |
| `scripts/tools/export_ocean_downscaling_products_bydepth_to_csv.sh` | `contains_word` | 2 | Retained |
| `scripts/tools/export_ocean_downscaling_products_bydepth_to_csv.sh` | `include_relative_path` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_bydepth_to_csv.sh` | `process_one_file` | 2 | Retained |
| `scripts/tools/export_ocean_downscaling_products_bydepth_to_csv.sh` | `sanitize_units` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_bydepth_to_csv.sh` | `depth_from_filename` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `contains_word` | 3 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `include_relative_path` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `include_resolution_path` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `process_one_file` | 2 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `is_ignored_var` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `parse_scale_factors` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `choose_main_var` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `choose_xy` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `axis_spacing` | 2 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `detect_variable_key` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `should_convert_future_uo_uvel_to_m_s` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_geotiff.sh` | `read_rows` | 2 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `contains_word` | 3 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `include_relative_path` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `include_resolution_path` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `process_one_file` | 2 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `is_ignored_var` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `sanitize_units` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `scalar_depth_from_dataset` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `depth_from_filename` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `depthless_label` | 1 | Retained |
| `scripts/tools/export_ocean_downscaling_products_to_parquet.sh` | `should_convert_future_uo_uvel_to_m_s` | 1 | Retained |
| `scripts/tools/fill_hindcast_baseline_coastal_gaps.sh` | `pick_main_var` | 2 | Archived with superseded script |
| `scripts/tools/fill_hindcast_baseline_coastal_gaps.sh` | `infer_xy_dims` | 1 | Archived with superseded script |
| `scripts/tools/fill_hindcast_baseline_coastal_gaps.sh` | `align_to_base_dims` | 1 | Archived with superseded script |
| `scripts/tools/fill_hindcast_baseline_coastal_gaps.sh` | `build_fill_geometry` | 1 | Archived with superseded script |
| `scripts/tools/fill_hindcast_baseline_coastal_gaps.sh` | `fill_slice_nearest` | 1 | Archived with superseded script |
| `scripts/tools/fill_hindcast_baseline_coastal_gaps.sh` | `fill_slice_distance_weighted` | 1 | Archived with superseded script |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `contains_word` | 1 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `future_resolutions_for_var` | 1 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `copy_one` | 1 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `dest_has_netcdf_files` | 1 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `copy_all_from_dir_parallel` | 2 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `find_downscaled_var_roots` | 1 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `copy_future_products` | 1 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `copy_baseline_product` | 13 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `uses_coastal_filled_baseline` | 1 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `hindcast_0p05_baseline_file` | 3 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `organize_one_baseline_var` | 2 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `organize_all_baselines` | 1 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `organize_one_future_var_window` | 2 | Retained |
| `scripts/tools/organize_ocean_downscaling_products.sh` | `organize_all_futures` | 1 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05.sh` | `detect_gridtype` | 2 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05.sh` | `resolve_method` | 2 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05.sh` | `process_file` | 2 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `detect_gridtype` | 2 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `resolve_method` | 2 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `process_file` | 2 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `pick_main_var` | 2 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `infer_xy_dims` | 1 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `align_to_base_dims` | 1 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `build_fill_geometry` | 1 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `fill_slice_nearest` | 1 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `fill_slice_distance_weighted` | 1 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `fill_slice_require_complete` | 1 | Retained |
| `scripts/tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh` | `finite_wet_neighbors` | 2 | Retained |
| `scripts/tools/split_ocean_downscaling_products_by_depth.sh` | `contains_word` | 2 | Retained |
| `scripts/tools/split_ocean_downscaling_products_by_depth.sh` | `include_relative_path` | 1 | Retained |
| `scripts/tools/split_ocean_downscaling_products_by_depth.sh` | `find_vertical_dim` | 2 | Retained |
| `scripts/tools/split_ocean_downscaling_products_by_depth.sh` | `depth_token_from_value` | 1 | Retained |
| `scripts/tools/split_ocean_downscaling_products_by_depth.sh` | `extract_all_levels` | 2 | Retained |
| `scripts/tools/split_ocean_downscaling_products_by_depth.sh` | `depth_token` | 1 | Retained |
| `scripts/tools/split_ocean_downscaling_products_by_depth.sh` | `process_one_file` | 2 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `contains_word` | 3 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `include_product_family` | 6 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `keep_future_product` | 3 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `keep_future_realization` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `copy_or_report` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `stage_one_file` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `stage_product_type` | 3 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `stage_manifests` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `keep_future_product` | 3 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `parse_float` | 3 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `geotiff_metadata` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `scale_factor_from_metadata` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `encoded_stats_from_metadata` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `refresh_manifest_metadata` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `iter_manifest_rows` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `staged_info_for_row` | 1 | Retained |
| `scripts/tools/stage_ocean_downscaling_sample_products.sh` | `write_manifest` | 2 | Retained |
