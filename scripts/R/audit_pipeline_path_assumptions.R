#!/usr/bin/env Rscript
# ==============================================================================
#  Pipeline path-assumption audit
#
#  Ownership:
#    This code was created by Isaac Brito-Morales
#    (ibrito@conservation.org)
#
#  Purpose:
#    Scan repository scripts for path, layout, variable, and workflow-stage
#    assumptions that may need review before moving IPCC/ESGF processing to the
#    new /home/SB5 storage layout.
#
#  Notes:
#    - This script is read-only with respect to code.
#    - It writes a CSV audit report for review.
# ==============================================================================

options(stringsAsFactors = FALSE)

env_value <- function(name, default = "") {
  value <- Sys.getenv(name, unset = default)
  if (!nzchar(value)) default else value
}

repo_root <- normalizePath(getwd(), mustWork = TRUE)
scan_root <- env_value("SCAN_ROOT", file.path(repo_root, "scripts"))
out_file <- env_value(
  "OUT_FILE",
  file.path(repo_root, "data", "manifests", "pipeline_path_assumptions_audit.csv")
)

patterns <- data.frame(
  category = c(
    "old_ipcc_download_root",
    "old_ipcc_monthly_root",
    "new_ipcc_root",
    "old_glorys_root",
    "old_hindcast_root",
    "old_rcp85_root",
    "hardcoded_chl_o2",
    "future_windows_missing_2030",
    "stage_requires_on_glorys",
    "stage_requires_parts",
    "member_auto_logic",
    "model_scenario_var_layout",
    "two_dimensional_var",
    "sea_ice_var"
  ),
  pattern = c(
    "/home/SB5/ipcc_esgf_downloads",
    "/home/SB5/ipcc_esgf_monthly_1deg",
    "/home/SB5/ipcc_esgf",
    "/home/SB5/glorys12v1_monthly_0p05",
    "/home/SB5/global_ocean_biogeochemistry_hindcast",
    "/home/SB5/rcp85",
    "VARS=\\(|chl|o2",
    "2030-2060|FUT2030|2030-01-01",
    "on_glorys",
    "parts",
    "MEMBER=|ipcc_esgf_resolve_member|member_id",
    "\\$\\{model\\}/\\$\\{scen\\}/\\$\\{v\\}|<model>/<scenario>/<var>|<model>/<scenario>/<variable>",
    "zos|mlotst",
    "siconc|SImon"
  ),
  interpretation = c(
    "References legacy IPCC/ESGF download root.",
    "References legacy IPCC/ESGF processed monthly root.",
    "References new IPCC/ESGF root.",
    "References legacy GLORYS root; may need reanalysis-root support later.",
    "References legacy hindcast roots; may need reanalysis-root support later.",
    "References legacy CMIP5/RCP85 root; target is /home/SB5/ipcc_esgf/cmip5_rcp85.",
    "May contain hard-coded variable lists that need expansion beyond chl/o2.",
    "Mentions 2030-2060 support. Absence in future-window runners is a review flag.",
    "Assumes an on_glorys stage; 2D variables may need to skip vertical interpolation.",
    "Assumes a parts stage from monthly regridding.",
    "Uses or resolves member/variant labels.",
    "May assume old <model>/<scenario>/<var> layout rather than <model>/<member>/<scenario>/<var>.",
    "Mentions 2D variables that should not go through vertical interpolation.",
    "Mentions sea-ice concentration or SImon table."
  ),
  stringsAsFactors = FALSE
)

script_files <- list.files(
  scan_root,
  pattern = "\\.(sh|R)$|\\.slurm\\.sh$",
  recursive = TRUE,
  full.names = TRUE
)
script_files <- script_files[file.info(script_files)$isdir == FALSE]
script_files <- script_files[basename(script_files) != "audit_pipeline_path_assumptions.R"]

matches <- list()
match_i <- 1L

for (file in script_files) {
  lines <- readLines(file, warn = FALSE)
  rel_file <- sub(paste0("^", gsub("([\\W])", "\\\\\\1", repo_root), "/?"), "", file)

  for (p in seq_len(nrow(patterns))) {
    hit <- grepl(patterns$pattern[[p]], lines, perl = TRUE)
    if (!any(hit)) next

    hit_lines <- which(hit)
    for (line_no in hit_lines) {
      matches[[match_i]] <- data.frame(
        file = rel_file,
        line = line_no,
        category = patterns$category[[p]],
        interpretation = patterns$interpretation[[p]],
        text = trimws(lines[[line_no]]),
        stringsAsFactors = FALSE
      )
      match_i <- match_i + 1L
    }
  }
}

if (length(matches) == 0) {
  audit <- data.frame(
    file = character(),
    line = integer(),
    category = character(),
    interpretation = character(),
    text = character()
  )
} else {
  audit <- do.call(rbind, matches)
  audit <- audit[order(audit$file, audit$line, audit$category), , drop = FALSE]
}

dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
write.csv(audit, out_file, row.names = FALSE, na = "")

summary <- aggregate(
  file ~ category,
  audit,
  function(x) length(unique(x))
)
names(summary) <- c("category", "files")
summary <- summary[order(summary$category), , drop = FALSE]

message("Wrote audit: ", out_file)
message("Matches: ", nrow(audit))
if (nrow(summary) > 0) {
  message("Files by category:")
  for (i in seq_len(nrow(summary))) {
    message("  ", summary$category[[i]], ": ", summary$files[[i]])
  }
}
