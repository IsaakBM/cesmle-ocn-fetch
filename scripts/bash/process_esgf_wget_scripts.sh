#!/usr/bin/env bash
# ==============================================================================
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=esgf_wget
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH -t 1-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/esgf_wget_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/esgf_wget_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Generic processor for ESGF/IPCC wget scripts
#
# Purpose:
#   - Read one wget script, many wget scripts, or a directory of wget scripts
#   - Extract the embedded download table from each file
#   - Write a manifest with filename, URL, checksum type, and checksum
#   - Optionally download the files with checksum verification
#
# Expected wget script structure:
#   download_files="$(cat <<EOF--dataset.file.url.chksum_type.chksum
#   'file.nc' 'http://...' 'SHA256' 'abcdef...'
#   EOF--dataset.file.url.chksum_type.chksum
#   )"
#
# Notes:
#   - Default mode is parse only
#   - Download mode is enabled with --download
#   - By default, files are grouped by source script name
#   - Downloads can run in parallel; default is 2 workers
# ==============================================================================

SCRIPT_NAME="$(basename "$0")"
DEFAULT_PATTERN="wget_script_*.sh"
DEFAULT_OUTDIR="/home/sandbox-sparc/cesmle-ocn-fetch/esgf_downloads"
DEFAULT_MANIFEST="/home/sandbox-sparc/cesmle-ocn-fetch/logs/esgf_manifest.csv"

PATTERN="${PATTERN:-$DEFAULT_PATTERN}"
OUTDIR="${OUTDIR:-$DEFAULT_OUTDIR}"
MANIFEST="${MANIFEST:-$DEFAULT_MANIFEST}"
LAYOUT="${LAYOUT:-by-script}"
DOWNLOAD=0
FORCE=0
QUIET=0
JOBS="${JOBS:-${SLURM_CPUS_PER_TASK:-2}}"

usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [options] <wget_script_or_directory> [more_inputs...]

Options:
  --manifest <file>   Output manifest CSV path
  --outdir <dir>      Download destination root
  --pattern <glob>    Pattern used when an input is a directory
  --layout <mode>     flat | by-script
  --download          Download files after parsing
  --jobs <n>          Parallel downloads when using --download
  --force             Overwrite files that already exist
  --quiet             Print less output
  -h, --help          Show this help

Examples:
  ${SCRIPT_NAME} wget_script_2026-4-10_13-31-39.sh
  ${SCRIPT_NAME} --manifest /path/to/manifest.csv /path/to/wget_scripts/
  ${SCRIPT_NAME} --download --jobs 2 --outdir /home/SB5/ipcc /path/to/wget_scripts/
EOF
}

log() {
  if [[ "$QUIET" -eq 0 ]]; then
    echo "$@"
  fi
}

require_commands() {
  local cmds=(awk sed grep find wget stat sort mktemp)
  local cmd
  for cmd in "${cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "ERROR: Required command not found in PATH: $cmd" >&2
      exit 1
    fi
  done
}

checksum_file() {
  local file="$1"
  local chk_type="$2"

  case "${chk_type,,}" in
    sha256)
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
      elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
      else
        echo "ERROR: No SHA256 checksum command available" >&2
        return 1
      fi
      ;;
    md5)
      if command -v md5sum >/dev/null 2>&1; then
        md5sum "$file" | awk '{print $1}'
      elif command -v md5 >/dev/null 2>&1; then
        md5 "$file" | sed -n 's/.*= //p'
      else
        echo "ERROR: No MD5 checksum command available" >&2
        return 1
      fi
      ;;
    *)
      echo "ERROR: Unsupported checksum type: $chk_type" >&2
      return 1
      ;;
  esac
}

mtime_file() {
  local file="$1"
  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
  else
    stat -f %m "$file"
  fi
}

append_script_entries() {
  local script="$1"
  local tmp_entries="$2"
  local line

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^\'([^\']+)\'[[:space:]]+\'([^\']+)\'[[:space:]]+\'([^\']+)\'[[:space:]]+\'([^\']+)\'$ ]]; then
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$script" \
        "${BASH_REMATCH[1]}" \
        "${BASH_REMATCH[2]}" \
        "$(printf '%s' "${BASH_REMATCH[3]}" | tr '[:upper:]' '[:lower:]')" \
        "$(printf '%s' "${BASH_REMATCH[4]}" | tr '[:upper:]' '[:lower:]')" \
        >> "$tmp_entries"
    fi
  done < <(
    sed -n '/download_files="\$(cat <<EOF--dataset.file.url.chksum_type.chksum/,/EOF--dataset.file.url.chksum_type.chksum/p' "$script" \
      | sed '1d;$d'
  )
}

collect_inputs() {
  local tmp_scripts="$1"
  shift

  local input path
  for input in "$@"; do
    if [[ -d "$input" ]]; then
      find "$input" -type f -name "$PATTERN" | sort >> "$tmp_scripts"
    else
      printf '%s\n' "$input" >> "$tmp_scripts"
    fi
  done
}

download_one() {
  local script="$1"
  local file="$2"
  local url="$3"
  local chk_type="$4"
  local chk_value="$5"
  local target_dir target tmp actual

  if [[ "$LAYOUT" == "flat" ]]; then
    target_dir="$OUTDIR"
  else
    target_dir="${OUTDIR}/$(basename "$script" .sh)"
  fi

  mkdir -p "$target_dir"
  target="${target_dir}/${file}"
  tmp="${target}.part"

  if [[ -f "$target" && "$FORCE" -eq 0 ]]; then
    actual="$(checksum_file "$target" "$chk_type")"
    if [[ "$actual" == "$chk_value" ]]; then
      log "EXISTS      $target"
      return 0
    fi
    echo "ERROR: Existing file checksum mismatch: $target" >&2
    echo "       Use --force to overwrite it." >&2
    return 1
  fi

  rm -f "$tmp"
  log "DOWNLOADING $file"
  wget -O "$tmp" "$url"

  actual="$(checksum_file "$tmp" "$chk_type")"
  if [[ "$actual" != "$chk_value" ]]; then
    rm -f "$tmp"
    echo "ERROR: Checksum failed for $file" >&2
    echo "       Expected: $chk_value" >&2
    echo "       Got     : $actual" >&2
    return 1
  fi

  mv -f "$tmp" "$target"
  log "DONE        $target"
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

INPUTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      MANIFEST="$2"
      shift 2
      ;;
    --outdir)
      OUTDIR="$2"
      shift 2
      ;;
    --pattern)
      PATTERN="$2"
      shift 2
      ;;
    --layout)
      LAYOUT="$2"
      shift 2
      ;;
    --download)
      DOWNLOAD=1
      shift
      ;;
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      INPUTS+=("$1")
      shift
      ;;
  esac
done

if [[ "${#INPUTS[@]}" -eq 0 ]]; then
  echo "ERROR: At least one input file or directory is required." >&2
  usage
  exit 1
fi

if [[ "$LAYOUT" != "flat" && "$LAYOUT" != "by-script" ]]; then
  echo "ERROR: --layout must be 'flat' or 'by-script'" >&2
  exit 1
fi

if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
  echo "ERROR: --jobs must be a positive integer" >&2
  exit 1
fi

require_commands
mkdir -p "$(dirname "$MANIFEST")"

if [[ "$DOWNLOAD" -eq 1 ]]; then
  mkdir -p "$OUTDIR"
fi

TMP_SCRIPTS="$(mktemp)"
TMP_ENTRIES="$(mktemp)"
trap 'rm -f "$TMP_SCRIPTS" "$TMP_ENTRIES"' EXIT

collect_inputs "$TMP_SCRIPTS" "${INPUTS[@]}"

sort -u "$TMP_SCRIPTS" -o "$TMP_SCRIPTS"

if [[ ! -s "$TMP_SCRIPTS" ]]; then
  echo "ERROR: No input scripts found." >&2
  exit 1
fi

while IFS= read -r script; do
  if [[ ! -f "$script" ]]; then
    echo "ERROR: Input not found: $script" >&2
    exit 1
  fi
  append_script_entries "$script" "$TMP_ENTRIES"
done < "$TMP_SCRIPTS"

if [[ ! -s "$TMP_ENTRIES" ]]; then
  echo "ERROR: No downloadable entries found in the provided scripts." >&2
  exit 1
fi

{
  echo "script,filename,url,checksum_type,checksum"
  awk -F '\t' '{printf "\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"\n",$1,$2,$3,$4,$5}' "$TMP_ENTRIES"
} > "$MANIFEST"

SCRIPT_COUNT="$(wc -l < "$TMP_SCRIPTS" | awk '{print $1}')"
FILE_COUNT="$(wc -l < "$TMP_ENTRIES" | awk '{print $1}')"

log "Scripts parsed : $SCRIPT_COUNT"
log "Files found    : $FILE_COUNT"
log "Manifest       : $MANIFEST"
if [[ "$DOWNLOAD" -eq 1 ]]; then
  log "Parallel jobs  : $JOBS"
fi

if [[ "$DOWNLOAD" -eq 1 ]]; then
  export OUTDIR LAYOUT FORCE QUIET
  export -f log checksum_file download_one

  xargs -P "$JOBS" -n 5 bash -c '
    download_one "$1" "$2" "$3" "$4" "$5"
  ' _ < <(tr '\t' '\n' < "$TMP_ENTRIES")

  log "Download step complete."
fi

log "Done."
