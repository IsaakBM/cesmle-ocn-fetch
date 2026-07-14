#!/usr/bin/env Rscript
# ==============================================================================
#  IPCC/ESGF NCI CMIP6 discovery manifest builder
#
#  Ownership:
#    This code was created for Isaac Brito-Morales
#    (ibrito@conservation.org)
#
#  Purpose:
#    Query the ESGF NCI search API for CMIP6 monthly ocean products needed by
#    the IPCC/ESGF downscaling workflow, then write file and coverage manifests
#    that can be reviewed before large NetCDF files are fetched.
#
#  Notes:
#    - This script only discovers files. It does not download NetCDF data.
#    - Default filters target Omon, gn, historical/SSP products, and the first
#      available realization per model/experiment/variable.
#    - Use SOURCE_IDS to restrict the scan to known candidate models.
# ==============================================================================

options(stringsAsFactors = FALSE)

required_packages <- c("jsonlite")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop(
    "Missing required R package(s): ",
    paste(missing_packages, collapse = ", "),
    "\nInstall them before running this script."
  )
}

env_value <- function(name, default = "") {
  value <- Sys.getenv(name, unset = default)
  if (!nzchar(value)) default else value
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(x)) y else x
}

split_env <- function(name, default) {
  value <- env_value(name, paste(default, collapse = " "))
  parts <- unlist(strsplit(value, "[,[:space:]]+"))
  parts[nzchar(parts)]
}

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg) > 0) sub("^--file=", "", script_arg[[1]]) else ""
repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = FALSE)
if (!dir.exists(file.path(repo_root, "scripts"))) {
  repo_root <- normalizePath(getwd(), mustWork = TRUE)
}

api_url <- env_value("ESGF_API_URL", "https://esgf.nci.org.au/esg-search/search")
out_dir <- env_value("OUT_DIR", file.path(repo_root, "data", "manifests"))
out_prefix <- env_value("OUT_PREFIX", "ipcc_esgf_nci_cmip6")
rows <- as.integer(env_value("ESGF_ROWS", "500"))
max_pages <- as.integer(env_value("ESGF_MAX_PAGES", "200"))

variables <- split_env(
  "VARS",
  c("thetao", "so", "ph", "o2", "chl", "uo", "vo", "zooc", "zos", "mlotst")
)
experiments <- split_env("EXPERIMENTS", c("historical", "ssp126", "ssp245", "ssp585"))
source_ids <- split_env("SOURCE_IDS", character())
table_id <- env_value("TABLE_ID", "Omon")
grid_label <- env_value("GRID_LABEL", "gn")
project <- env_value("PROJECT", "CMIP6")
latest <- env_value("LATEST", "true")
replica <- env_value("REPLICA", "")

windows <- data.frame(
  experiment_group = c("historical", "future", "future", "future"),
  window = c("2006-2014", "2030-2060", "2050-2060", "2090-2100"),
  start = as.Date(c("2006-01-01", "2030-01-01", "2050-01-01", "2090-01-01")),
  end = as.Date(c("2014-12-31", "2060-12-31", "2060-12-31", "2100-12-31"))
)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

message("ESGF API: ", api_url)
message("Variables: ", paste(variables, collapse = ", "))
message("Experiments: ", paste(experiments, collapse = ", "))
message("Table/grid: ", table_id, "/", grid_label)
if (length(source_ids) > 0) {
  message("Source IDs: ", paste(source_ids, collapse = ", "))
} else {
  message("Source IDs: all available models from ESGF query results")
}

query_url <- function(params) {
  encoded <- vapply(
    names(params),
    function(name) {
      paste0(utils::URLencode(name, reserved = TRUE), "=", utils::URLencode(as.character(params[[name]]), reserved = TRUE))
    },
    character(1)
  )
  paste0(api_url, "?", paste(encoded, collapse = "&"))
}

first_value <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_character_)
  as.character(x[[1]])
}

http_url <- function(urls) {
  if (is.null(urls) || length(urls) == 0) return(NA_character_)
  hits <- urls[grepl("\\|HTTPServer$", urls)]
  if (length(hits) == 0) hits <- urls[grepl("application/netcdf", urls)]
  if (length(hits) == 0) return(NA_character_)
  sub("\\|.*$", "", hits[[1]])
}

parse_time_range <- function(title) {
  match <- regexec("_(\\d{4})(\\d{2})?-(\\d{4})(\\d{2})?\\.nc$", title)
  parts <- regmatches(title, match)[[1]]
  if (length(parts) == 0) {
    return(data.frame(time_start = as.Date(NA), time_end = as.Date(NA)))
  }

  start_year <- parts[[2]]
  start_month <- ifelse(nzchar(parts[[3]]), parts[[3]], "01")
  end_year <- parts[[4]]
  end_month <- ifelse(nzchar(parts[[5]]), parts[[5]], "12")

  time_start <- as.Date(sprintf("%s-%s-01", start_year, start_month))
  end_first <- as.Date(sprintf("%s-%s-01", end_year, end_month))
  time_end <- seq(end_first, by = "1 month", length.out = 2)[2] - 1

  data.frame(time_start = time_start, time_end = time_end)
}

member_key <- function(member_id) {
  match <- regexec("^r([0-9]+)i([0-9]+)p([0-9]+)f([0-9]+)$", member_id)
  parts <- regmatches(member_id, match)[[1]]
  if (length(parts) == 0) return(sprintf("%09d_%09d_%09d_%09d", 999999999, 999999999, 999999999, 999999999))
  nums <- as.integer(parts[2:5])
  sprintf("%09d_%09d_%09d_%09d", nums[[1]], nums[[2]], nums[[3]], nums[[4]])
}

window_rows_for_experiment <- function(experiment_id) {
  if (identical(experiment_id, "historical")) {
    windows[windows$experiment_group == "historical", , drop = FALSE]
  } else {
    windows[windows$experiment_group == "future", , drop = FALSE]
  }
}

file_overlaps_window <- function(file_start, file_end, window_start, window_end) {
  !is.na(file_start) && !is.na(file_end) && file_start <= window_end && file_end >= window_start
}

doc_to_row <- function(doc) {
  title <- first_value(doc$title)
  time_range <- parse_time_range(title)

  data.frame(
    id = first_value(doc$id),
    dataset_id = first_value(doc$dataset_id),
    source_id = first_value(doc$source_id),
    institution_id = first_value(doc$institution_id),
    experiment_id = first_value(doc$experiment_id),
    member_id = first_value(doc$member_id %||% doc$variant_label),
    table_id = first_value(doc$table_id),
    variable_id = first_value(doc$variable_id),
    grid_label = first_value(doc$grid_label),
    version = first_value(doc$version),
    title = title,
    time_start = time_range$time_start,
    time_end = time_range$time_end,
    size_bytes = as.numeric(doc$size %||% NA_real_),
    checksum_type = first_value(doc$checksum_type),
    checksum = first_value(doc$checksum),
    data_node = first_value(doc$data_node),
    http_url = http_url(doc$url),
    stringsAsFactors = FALSE
  )
}

fetch_file_rows <- function(variable_id, experiment_id, source_id = NULL) {
  row_parts <- list()
  row_part_i <- 1L
  start <- 0L

  for (page in seq_len(max_pages)) {
    params <- list(
      format = "application/solr+json",
      project = project,
      type = "File",
      latest = latest,
      table_id = table_id,
      variable_id = variable_id,
      experiment_id = experiment_id,
      grid_label = grid_label,
      limit = rows,
      offset = start
    )
    if (nzchar(replica)) params$replica <- replica
    if (!is.null(source_id)) params$source_id <- source_id

    url <- query_url(params)
    message("Query ", variable_id, " ", experiment_id, if (!is.null(source_id)) paste0(" ", source_id) else "", " offset=", start)

    response <- jsonlite::fromJSON(url, simplifyVector = FALSE)
    docs <- response$response$docs
    if (length(docs) == 0) break

    row_parts[[row_part_i]] <- do.call(rbind, lapply(docs, doc_to_row))
    row_part_i <- row_part_i + 1L

    num_found <- response$response$numFound
    start <- start + length(docs)
    if (start >= num_found) break
  }

  if (length(row_parts) == 0) {
    return(data.frame())
  }
  do.call(rbind, row_parts)
}

file_parts <- list()
file_part_i <- 1L
for (variable_id in variables) {
  for (experiment_id in experiments) {
    if (length(source_ids) > 0) {
      for (source_id in source_ids) {
        file_parts[[file_part_i]] <- fetch_file_rows(variable_id, experiment_id, source_id)
        file_part_i <- file_part_i + 1L
      }
    } else {
      file_parts[[file_part_i]] <- fetch_file_rows(variable_id, experiment_id)
      file_part_i <- file_part_i + 1L
    }
  }
}

file_parts <- file_parts[vapply(file_parts, nrow, integer(1)) > 0]
if (length(file_parts) == 0) {
  stop("No ESGF files returned for the configured query.")
}

message("Combining ESGF file rows")
files <- do.call(rbind, file_parts)
file_key <- paste(files$id, files$http_url, files$checksum, sep = "|")
files <- files[!duplicated(file_key), , drop = FALSE]
files <- files[!is.na(files$http_url) & nzchar(files$http_url), , drop = FALSE]

message("Selecting first available members")
files$member_sort_key <- vapply(files$member_id, member_key, character(1))
files <- files[order(
  files$source_id,
  files$experiment_id,
  files$variable_id,
  files$member_sort_key,
  files$time_start,
  files$title
), , drop = FALSE]

first_members <- unique(files[, c("source_id", "experiment_id", "variable_id", "member_id", "member_sort_key")])
first_members <- first_members[order(
  first_members$source_id,
  first_members$experiment_id,
  first_members$variable_id,
  first_members$member_sort_key
), , drop = FALSE]
first_members <- first_members[!duplicated(first_members[, c("source_id", "experiment_id", "variable_id")]), , drop = FALSE]
first_members$is_first_available_member <- TRUE

files <- merge(
  files,
  first_members[, c("source_id", "experiment_id", "variable_id", "member_id", "is_first_available_member")],
  by = c("source_id", "experiment_id", "variable_id", "member_id"),
  all.x = TRUE
)
files$is_first_available_member[is.na(files$is_first_available_member)] <- FALSE

selected_files <- files[files$is_first_available_member, , drop = FALSE]
selected_files$url_preference <- ifelse(
  grepl("esgf\\.nci\\.org\\.au", selected_files$http_url),
  0L,
  ifelse(grepl("^https://", selected_files$http_url), 1L, 2L)
)
selected_files <- selected_files[order(
  selected_files$source_id,
  selected_files$experiment_id,
  selected_files$variable_id,
  selected_files$member_sort_key,
  selected_files$time_start,
  selected_files$url_preference,
  selected_files$data_node
), , drop = FALSE]
selected_file_key <- paste(
  selected_files$source_id,
  selected_files$experiment_id,
  selected_files$variable_id,
  selected_files$member_id,
  selected_files$title,
  selected_files$checksum,
  sep = "|"
)
selected_files <- selected_files[!duplicated(selected_file_key), , drop = FALSE]

message("Building coverage tables")
coverage_parts <- list()
part_i <- 1L
for (source_id in sort(unique(selected_files$source_id))) {
  for (experiment_id in experiments) {
    for (variable_id in variables) {
      subset_files <- selected_files[
        selected_files$source_id == source_id &
          selected_files$experiment_id == experiment_id &
          selected_files$variable_id == variable_id,
        ,
        drop = FALSE
      ]
      member_id <- if (nrow(subset_files) > 0) subset_files$member_id[[1]] else NA_character_

      exp_windows <- window_rows_for_experiment(experiment_id)
      for (w in seq_len(nrow(exp_windows))) {
        covered <- if (nrow(subset_files) > 0) {
          any(mapply(
            file_overlaps_window,
            subset_files$time_start,
            subset_files$time_end,
            MoreArgs = list(window_start = exp_windows$start[[w]], window_end = exp_windows$end[[w]])
          ))
        } else {
          FALSE
        }

        coverage_parts[[part_i]] <- data.frame(
          source_id = source_id,
          experiment_id = experiment_id,
          variable_id = variable_id,
          member_id = member_id,
          window = exp_windows$window[[w]],
          window_start = exp_windows$start[[w]],
          window_end = exp_windows$end[[w]],
          has_file_overlap = covered,
          file_count = nrow(subset_files),
          stringsAsFactors = FALSE
        )
        part_i <- part_i + 1L
      }
    }
  }
}

coverage <- do.call(rbind, coverage_parts)

summary <- aggregate(
  has_file_overlap ~ source_id,
  coverage,
  function(x) sum(x, na.rm = TRUE)
)
names(summary)[names(summary) == "has_file_overlap"] <- "covered_checks"
summary$total_checks <- as.integer(ave(coverage$has_file_overlap, coverage$source_id, FUN = length)[match(summary$source_id, coverage$source_id)])
summary$coverage_fraction <- summary$covered_checks / summary$total_checks
summary <- summary[order(-summary$coverage_fraction, -summary$covered_checks, summary$source_id), , drop = FALSE]

file_manifest_path <- file.path(out_dir, paste0(out_prefix, "_files.csv"))
selected_manifest_path <- file.path(out_dir, paste0(out_prefix, "_selected_first_member_files.csv"))
coverage_path <- file.path(out_dir, paste0(out_prefix, "_coverage.csv"))
summary_path <- file.path(out_dir, paste0(out_prefix, "_model_summary.csv"))
wget_manifest_path <- file.path(out_dir, paste0(out_prefix, "_wget_manifest.csv"))

message("Writing CSV manifests")
utils::write.csv(files, file_manifest_path, row.names = FALSE, na = "")
utils::write.csv(selected_files, selected_manifest_path, row.names = FALSE, na = "")
utils::write.csv(coverage, coverage_path, row.names = FALSE, na = "")
utils::write.csv(summary, summary_path, row.names = FALSE, na = "")

wget_manifest <- selected_files[, c("title", "http_url", "checksum_type", "checksum", "source_id", "experiment_id", "member_id", "variable_id", "table_id", "grid_label")]
names(wget_manifest)[1:2] <- c("filename", "url")
utils::write.csv(wget_manifest, wget_manifest_path, row.names = FALSE, na = "")

message("Wrote:")
message("  ", file_manifest_path)
message("  ", selected_manifest_path)
message("  ", coverage_path)
message("  ", summary_path)
message("  ", wget_manifest_path)
