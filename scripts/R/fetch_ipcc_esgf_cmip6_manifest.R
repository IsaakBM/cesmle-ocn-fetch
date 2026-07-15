#!/usr/bin/env Rscript
# ==============================================================================
#  IPCC/ESGF CMIP6 manifest fetcher
#
#  Ownership:
#    This code was created by Isaac Brito-Morales
#    (ibrito@conservation.org)
#
#  Purpose:
#    Read the CMIP6 ESGF wget manifest and fetch selected NetCDF files into the
#    agreed /home/SB5/ipcc_esgf/downloads tree.
#
#  Notes:
#    - Default mode is dry-run. No files are downloaded unless DOWNLOAD=yes.
#    - Downloads are organized as:
#        <out-root>/<model>/<member>/<experiment>/<variable>/<filename>
#    - Existing files are kept when their checksum matches the manifest.
#    - By default, files are limited to chunks that overlap the processing
#      windows used by this project:
#        historical: 2006-2014
#        future: 2030-2060, 2050-2060, 2090-2100
# ==============================================================================

options(stringsAsFactors = FALSE)

env_value <- function(name, default = "") {
  value <- Sys.getenv(name, unset = default)
  if (!nzchar(value)) default else value
}

split_env <- function(name, default = character()) {
  value <- env_value(name, paste(default, collapse = " "))
  if (!nzchar(value)) return(default)
  parts <- unlist(strsplit(value, "[,[:space:]]+"))
  parts[nzchar(parts)]
}

repo_root <- normalizePath(getwd(), mustWork = TRUE)
manifest <- env_value(
  "MANIFEST",
  file.path(repo_root, "data", "manifests", "ipcc_esgf_nci_cmip6_wget_manifest.csv")
)
out_root <- env_value("OUT_ROOT", "/home/SB5/ipcc_esgf/downloads")
download <- tolower(env_value("DOWNLOAD", "no")) %in% c("yes", "true", "1")
force <- tolower(env_value("FORCE", "no")) %in% c("yes", "true", "1")
limit <- as.integer(env_value("LIMIT", "0"))
write_plan <- env_value("WRITE_PLAN", "")
time_filter <- tolower(env_value("TIME_FILTER", "yes")) %in% c("yes", "true", "1")

models <- split_env("MODELS")
members <- split_env("MEMBERS")
experiments <- split_env("EXPERIMENTS")
variables <- split_env("VARS")

windows <- data.frame(
  experiment_group = c("historical", "future", "future", "future"),
  label = c("2006-2014", "2030-2060", "2050-2060", "2090-2100"),
  start = as.Date(c("2006-01-01", "2030-01-01", "2050-01-01", "2090-01-01")),
  end = as.Date(c("2014-12-31", "2060-12-31", "2060-12-31", "2100-12-31"))
)

file_time_range <- function(filename) {
  matched <- regmatches(filename, regexpr("[0-9]{6}-[0-9]{6}(?=\\.nc$)", filename, perl = TRUE))
  if (length(matched) == 0 || identical(matched, character(0)) || is.na(matched)) {
    return(list(start = as.Date(NA), end = as.Date(NA)))
  }

  parts <- strsplit(matched, "-", fixed = TRUE)[[1]]
  start <- as.Date(paste0(substr(parts[[1]], 1, 4), "-", substr(parts[[1]], 5, 6), "-01"))
  end_month <- as.Date(paste0(substr(parts[[2]], 1, 4), "-", substr(parts[[2]], 5, 6), "-01"))
  end <- seq(end_month, by = "month", length.out = 2)[[2]] - 1
  list(start = start, end = end)
}

overlaps_window <- function(file_start, file_end, window_start, window_end) {
  !is.na(file_start) && !is.na(file_end) && file_start <= window_end && file_end >= window_start
}

needed_for_windows <- function(filename, experiment_id) {
  range <- file_time_range(filename)
  experiment_group <- if (identical(experiment_id, "historical")) "historical" else "future"
  candidate_windows <- windows[windows$experiment_group == experiment_group, , drop = FALSE]

  any(vapply(
    seq_len(nrow(candidate_windows)),
    function(i) overlaps_window(range$start, range$end, candidate_windows$start[[i]], candidate_windows$end[[i]]),
    logical(1)
  ))
}

if (!file.exists(manifest)) {
  stop("Manifest not found: ", manifest)
}

required_commands <- c("wget")
if (download) {
  command_available <- vapply(
    required_commands,
    function(command) nzchar(Sys.which(command)),
    logical(1)
  )
  missing_commands <- required_commands[!command_available]
  if (length(missing_commands) > 0) {
    stop("Missing required command(s): ", paste(missing_commands, collapse = ", "))
  }
}

manifest_rows <- read.csv(manifest, stringsAsFactors = FALSE, check.names = FALSE)

keep <- rep(TRUE, nrow(manifest_rows))
if (length(models) > 0) keep <- keep & manifest_rows$source_id %in% models
if (length(members) > 0) keep <- keep & manifest_rows$member_id %in% members
if (length(experiments) > 0) keep <- keep & manifest_rows$experiment_id %in% experiments
if (length(variables) > 0) keep <- keep & manifest_rows$variable_id %in% variables

selected <- manifest_rows[keep, , drop = FALSE]
if (time_filter && nrow(selected) > 0) {
  keep_time <- vapply(
    seq_len(nrow(selected)),
    function(i) needed_for_windows(selected$filename[[i]], selected$experiment_id[[i]]),
    logical(1)
  )
  selected <- selected[keep_time, , drop = FALSE]
}

if (!is.na(limit) && limit > 0 && nrow(selected) > limit) {
  selected <- selected[seq_len(limit), , drop = FALSE]
}

target_path <- function(row) {
  file.path(
    out_root,
    row[["source_id"]],
    row[["member_id"]],
    row[["experiment_id"]],
    row[["variable_id"]],
    row[["filename"]]
  )
}

checksum_file <- function(path, checksum_type) {
  type <- tolower(checksum_type)
  if (type == "sha256") {
    if (nzchar(Sys.which("sha256sum"))) {
      return(strsplit(system2("sha256sum", path, stdout = TRUE), "[[:space:]]+")[[1]][[1]])
    }
    if (nzchar(Sys.which("shasum"))) {
      return(strsplit(system2("shasum", c("-a", "256", path), stdout = TRUE), "[[:space:]]+")[[1]][[1]])
    }
  }
  if (type == "md5") {
    if (nzchar(Sys.which("md5sum"))) {
      return(strsplit(system2("md5sum", path, stdout = TRUE), "[[:space:]]+")[[1]][[1]])
    }
    if (nzchar(Sys.which("md5"))) {
      return(sub(".*= ", "", system2("md5", path, stdout = TRUE)))
    }
  }
  stop("Unsupported checksum type or missing checksum command: ", checksum_type)
}

write_fetch_plan <- function(rows, path) {
  plan <- rows[, c(
    "filename", "source_id", "member_id", "experiment_id", "variable_id",
    "url", "checksum_type", "checksum"
  ), drop = FALSE]
  plan$target <- vapply(seq_len(nrow(rows)), function(i) target_path(rows[i, , drop = FALSE]), character(1))
  plan <- plan[, c(
    "filename", "source_id", "member_id", "experiment_id", "variable_id",
    "target", "url", "checksum_type", "checksum"
  )]
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.csv(plan, path, row.names = FALSE, na = "")
}

download_one <- function(row) {
  target <- target_path(row)
  expected <- tolower(row[["checksum"]])
  checksum_type <- row[["checksum_type"]]

  if (file.exists(target) && !force) {
    actual <- tolower(checksum_file(target, checksum_type))
    if (identical(actual, expected)) {
      return("exists")
    }
    stop(
      "Existing file checksum mismatch: ", target,
      "\nExpected: ", expected,
      "\nActual  : ", actual,
      "\nUse FORCE=yes to overwrite."
    )
  }

  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(target, ".part")
  if (file.exists(tmp)) unlink(tmp)

  status <- system2("wget", c("-O", tmp, row[["url"]]))
  if (!identical(status, 0L)) {
    stop("wget failed for: ", row[["url"]])
  }

  actual <- tolower(checksum_file(tmp, checksum_type))
  if (!identical(actual, expected)) {
    unlink(tmp)
    stop(
      "Downloaded file checksum mismatch: ", target,
      "\nExpected: ", expected,
      "\nActual  : ", actual
    )
  }

  file.rename(tmp, target)
  "downloaded"
}

if (nrow(selected) == 0) {
  message("No manifest rows matched the requested filters.")
  quit(status = 0)
}

if (nzchar(write_plan)) {
  write_fetch_plan(selected, write_plan)
}

message("Manifest: ", manifest)
message("Output root: ", out_root)
message("Selected files: ", nrow(selected))
message("Time filter: ", if (time_filter) "on" else "off")
message("Mode: ", if (download) "download" else "dry-run")

if (!download) {
  preview_n <- min(20L, nrow(selected))
  for (i in seq_len(preview_n)) {
    message("DRYRUN ", target_path(selected[i, , drop = FALSE]))
  }
  if (nrow(selected) > preview_n) {
    message("DRYRUN ... ", nrow(selected) - preview_n, " more files")
  }
  quit(status = 0)
}

downloaded <- 0L
existing <- 0L
for (i in seq_len(nrow(selected))) {
  message("[", i, "/", nrow(selected), "] ", target_path(selected[i, , drop = FALSE]))
  status <- download_one(selected[i, , drop = FALSE])
  if (identical(status, "downloaded")) downloaded <- downloaded + 1L
  if (identical(status, "exists")) existing <- existing + 1L
}

message("Downloaded: ", downloaded)
message("Already complete: ", existing)
