#!/bin/bash
#
# ==============================================================================
#  Generic temporal aggregation + regridder
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Build monthly means from daily files organized as YEAR/MONTH
#    - Or skip temporal aggregation when inputs are already monthly
#    - Or regrid one-or-more monthly time-series files directly
#    - Process one variable (VAR) using either YEAR/MONTH or time-series input
#    - Regrid outputs to a target lon/lat grid using a chosen CDO method
#    - Run monthly or file-level work in parallel
#    - Handle temp files safely
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=temporal_regrid
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=512G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/temporal_regrid_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/temporal_regrid_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail

# ==============================================================================
# Required env vars (passed at sbatch time)
#   DATASET_LABEL : short dataset label for logs/messages
#   VAR           : variable to process
#   INROOT        : input root
#   OUTROOT       : output root
#   GRIDFILE      : CDO target grid file
#
# Optional env vars
#   INPUT_LAYOUT  : year_month | timeseries (default: year_month)
#   YEAR          : year to process when INPUT_LAYOUT=year_month
#   FILE_GLOB     : input file glob (default: *.nc*)
#   METHOD        : CDO remapping method or auto (default: remapbil)
#   AUTO_METHOD_DEFAULT     : method used in auto mode for regular grids
#                             (default: remapbil)
#   AUTO_METHOD_CURVILINEAR : method used in auto mode for curvilinear or
#                             unstructured grids (default: remapdis)
#   PARTS_SUBDIR  : output subdir under OUTROOT/VAR (default: parts)
#   TMP_SUBDIR    : temp subdir under OUTROOT/VAR (default: tmp)
#   MIN_FREE_GB   : minimum free space where TMP lives (default: 40)
#   INPUT_TIMESTEP: daily | monthly | auto (default: auto)
#                   used only for INPUT_LAYOUT=year_month
# ==============================================================================
DATASET_LABEL="${DATASET_LABEL:-dataset}"
VAR="${VAR:-}"
YEAR="${YEAR:-}"
INROOT="${INROOT:-}"
OUTROOT="${OUTROOT:-}"
GRIDFILE="${GRIDFILE:-}"

INPUT_LAYOUT="${INPUT_LAYOUT:-year_month}"
FILE_GLOB="${FILE_GLOB:-*.nc*}"
METHOD="${METHOD:-remapbil}"
AUTO_METHOD_DEFAULT="${AUTO_METHOD_DEFAULT:-remapbil}"
AUTO_METHOD_CURVILINEAR="${AUTO_METHOD_CURVILINEAR:-remapdis}"
PARTS_SUBDIR="${PARTS_SUBDIR:-parts}"
TMP_SUBDIR="${TMP_SUBDIR:-tmp}"
MIN_FREE_GB="${MIN_FREE_GB:-40}"
INPUT_TIMESTEP="${INPUT_TIMESTEP:-auto}"

if [[ -z "$VAR" || -z "$INROOT" || -z "$OUTROOT" || -z "$GRIDFILE" ]]; then
  echo "ERROR: Missing required environment variables."
  echo "Required: VAR, INROOT, OUTROOT, GRIDFILE"
  echo "Optional: DATASET_LABEL, INPUT_LAYOUT, YEAR, FILE_GLOB, METHOD, PARTS_SUBDIR, TMP_SUBDIR, MIN_FREE_GB, INPUT_TIMESTEP"
  exit 1
fi

if [[ "$INPUT_LAYOUT" != "year_month" && "$INPUT_LAYOUT" != "timeseries" ]]; then
  echo "ERROR: INPUT_LAYOUT must be one of: year_month, timeseries"
  exit 1
fi

if [[ "$INPUT_TIMESTEP" != "daily" && "$INPUT_TIMESTEP" != "monthly" && "$INPUT_TIMESTEP" != "auto" ]]; then
  echo "ERROR: INPUT_TIMESTEP must be one of: daily, monthly, auto"
  exit 1
fi

if [[ "$METHOD" != "auto" && "$METHOD" != remap* ]]; then
  echo "ERROR: METHOD must be auto or a valid CDO remap operator name"
  exit 1
fi

if [[ "$INPUT_LAYOUT" == "year_month" && -z "$YEAR" ]]; then
  echo "ERROR: YEAR must be set when INPUT_LAYOUT=year_month"
  exit 1
fi

if [[ ! -d "$INROOT" ]]; then
  echo "ERROR: Input root not found: $INROOT"
  exit 1
fi

if [[ ! -f "$GRIDFILE" ]]; then
  echo "ERROR: Grid file not found: $GRIDFILE"
  exit 1
fi

# ==============================================================================
# Paths
# ==============================================================================
OUTDIR="${OUTROOT}/${VAR}"
PARTS="${OUTDIR}/${PARTS_SUBDIR}"
mkdir -p "$PARTS"

LOGDIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"
mkdir -p "$LOGDIR"

# ==============================================================================
# Temp directory
# ==============================================================================
TMPBASE="${SLURM_TMPDIR:-${OUTROOT}/tmp}"
TMP_TAG="${YEAR:-all}"
TMPDIR="${TMPBASE}/${DATASET_LABEL}_${VAR}_${TMP_TAG}_${TMP_SUBDIR}"
mkdir -p "$TMPDIR"

# Free-space preflight
FREE_GB=$(df -BG "$TMPBASE" | awk 'NR==2 {gsub("G","",$4); print $4}')

if [[ -z "$FREE_GB" ]]; then
  echo "ERROR: Could not determine free space on: $TMPBASE"
  exit 1
fi

if [[ "$FREE_GB" -lt "$MIN_FREE_GB" ]]; then
  echo "ERROR: Low free space where TMP lives: ${FREE_GB}G free, need at least ${MIN_FREE_GB}G."
  echo "       Path checked: $TMPBASE"
  exit 1
fi

NPROC="${SLURM_CPUS_PER_TASK:-4}"

echo "================================================="
echo " DATASET        : $DATASET_LABEL"
echo " Input root     : $INROOT"
echo " Input layout   : $INPUT_LAYOUT"
echo " Variable       : $VAR"
if [[ -n "$YEAR" ]]; then
  echo " Year           : $YEAR"
fi
echo " File glob      : $FILE_GLOB"
echo " Output dir     : $OUTDIR"
echo " Parts dir      : $PARTS"
echo " Temp dir       : $TMPDIR"
echo " Grid           : $GRIDFILE"
echo " Method         : $METHOD"
if [[ "$METHOD" == "auto" ]]; then
  echo " Auto regular   : $AUTO_METHOD_DEFAULT"
  echo " Auto curvilin  : $AUTO_METHOD_CURVILINEAR"
fi
echo " Input timestep : $INPUT_TIMESTEP"
echo " CPUs           : ${SLURM_CPUS_PER_TASK:-4}"
echo " Parallel months: $NPROC"
echo " Free tmp fs    : ${FREE_GB}G (min ${MIN_FREE_GB}G)"
echo "================================================="

# ==============================================================================
# Build one month from YEAR/MONTH input
# ==============================================================================
detect_gridtype() {
  local src="$1"
  local gridtype

  gridtype="$(/usr/bin/cdo -s griddes "$src" 2>/dev/null | awk '$1 == "gridtype" {print $3; exit}')"
  if [[ -z "$gridtype" ]]; then
    gridtype="unknown"
  fi
  printf '%s\n' "$gridtype"
}

resolve_method() {
  local src="$1"
  local gridtype

  if [[ "$METHOD" != "auto" ]]; then
    printf '%s\n' "$METHOD"
    return 0
  fi

  gridtype="$(detect_gridtype "$src")"
  case "$gridtype" in
    curvilinear|unstructured)
      printf '%s\n' "$AUTO_METHOD_CURVILINEAR"
      ;;
    *)
      printf '%s\n' "$AUTO_METHOD_DEFAULT"
      ;;
  esac
}

process_month() {
  local yyyy="$1"
  local mm="$2"

  local inpath="${INROOT}/${yyyy}/${mm}"
  local out="${PARTS}/${DATASET_LABEL}_${VAR}_${yyyy}${mm}.monmean.$(basename "$GRIDFILE" .txt).nc"

  if [[ ! -d "$inpath" ]]; then
    echo "WARN: Missing directory: $inpath"
    return 0
  fi

  mapfile -t files < <(find "$inpath" -maxdepth 1 -type f -name "$FILE_GLOB" | sort)

  if [[ "${#files[@]}" -eq 0 ]]; then
    echo "WARN: No files found: $inpath"
    return 0
  fi

  local base="${DATASET_LABEL}_${VAR}_${yyyy}${mm}"
  local tmp_merge="${TMPDIR}/.${base}.merge.nc"
  local tmp_mon="${TMPDIR}/.${base}.monmean.nc"
  local tmp_out="${TMPDIR}/.${base}.out.nc"
  local source_file
  local mode
  local method_to_use
  local source_for_method

  trap 'rm -f "$tmp_merge" "$tmp_mon" "$tmp_out"' RETURN

  rm -f "$out"

  mode="$INPUT_TIMESTEP"
  if [[ "$mode" == "auto" ]]; then
    if [[ "${#files[@]}" -eq 1 ]]; then
      mode="monthly"
    else
      mode="daily"
    fi
  fi

  if [[ "$mode" == "monthly" ]]; then
    source_file="${files[0]}"
    source_for_method="$source_file"
    echo "INFO: ${yyyy}-${mm} detected as monthly input; skipping monmean"
    /usr/bin/cdo -L -O -P 1 -selname,"${VAR}" "$source_file" "$tmp_mon"
  else
    source_for_method="${files[0]}"
    echo "INFO: ${yyyy}-${mm} detected as daily input; computing monthly mean"
    /usr/bin/cdo -L -O -P 1 -selname,"${VAR}" -mergetime "${files[@]}" "$tmp_merge"
    /usr/bin/cdo -L -O -P 1 monmean "$tmp_merge" "$tmp_mon"
  fi

  method_to_use="$(resolve_method "$source_for_method")"
  echo "INFO: ${yyyy}-${mm} remap method resolved to: $method_to_use"
  /usr/bin/cdo -L -O -P 1 ${method_to_use},"${GRIDFILE}" "$tmp_mon" "$tmp_out"

  mv -f "$tmp_out" "$out"

  trap - RETURN
  echo "DONE: $out"
}

# ==============================================================================
# Regrid one time-series file directly
# ==============================================================================
process_timeseries_file() {
  local in="$1"
  local base stem out tmp method_to_use

  base="$(basename "$in")"
  stem="${base%.nc}"
  out="${PARTS}/${stem}.$(basename "$GRIDFILE" .txt).nc"
  tmp="${TMPDIR}/.${stem}.out.nc"

  trap 'rm -f "$tmp"' RETURN

  if [[ ! -f "$in" ]]; then
    echo "WARN: Missing file: $in"
    return 0
  fi

  rm -f "$out"

  echo "INFO: Regridding monthly time-series file: $base"
  method_to_use="$(resolve_method "$in")"
  echo "INFO: ${base} remap method resolved to: $method_to_use"
  /usr/bin/cdo -L -O -P 1 ${method_to_use},"${GRIDFILE}" -selname,"${VAR}" "$in" "$tmp"
  mv -f "$tmp" "$out"

  trap - RETURN
  echo "DONE: $out"
}

export -f detect_gridtype resolve_method process_month process_timeseries_file
export DATASET_LABEL INROOT OUTROOT OUTDIR PARTS TMPDIR VAR GRIDFILE METHOD AUTO_METHOD_DEFAULT AUTO_METHOD_CURVILINEAR FILE_GLOB INPUT_TIMESTEP

# ==============================================================================
# Main
# ==============================================================================
if [[ "$INPUT_LAYOUT" == "year_month" ]]; then
  printf "%s\n" 01 02 03 04 05 06 07 08 09 10 11 12 \
    | xargs -I{} -P "$NPROC" bash -c 'process_month "$@"' _ "$YEAR" {}
else
  mapfile -t TS_FILES < <(find "$INROOT" -maxdepth 1 -type f -name "$FILE_GLOB" | sort)

  if [[ "${#TS_FILES[@]}" -eq 0 ]]; then
    echo "ERROR: No matching time-series files found in: $INROOT"
    exit 1
  fi

  printf "%s\n" "${TS_FILES[@]}" \
    | xargs -I{} -P "$NPROC" bash -c 'process_timeseries_file "$@"' _ {}
fi

echo "All done: ${DATASET_LABEL} ${VAR} ${YEAR} (temporal aggregation + regrid)"
