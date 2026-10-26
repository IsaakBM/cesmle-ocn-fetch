#!/usr/bin/env bash
# ==============================================================================
#  GLORYS12v1 runner for generic climatology window builder from monthly files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit GLORYS baseline climatology jobs for selected variable(s) using
# the generic climatology builder for monthly-file collections.
#
# Notes:
#   - This runner is intended for monthly GLORYS12v1 files already harmonized to
#     a 0.05 x 0.05 degree grid.
#   - Expected input layout:
#       /home/SB5/reanalysis/glorys12v1/monthly_0p05/<var>/parts/*.nc
#   - Whole-window mode computes one climatology per variable over 2006-2014.
#     Monthly and seasonal products are explicit CLIMATOLOGY_MODE options.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/climatology_window_from_monthly_files.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS_DEFAULT=(
  bottomT
  mlotst
  so
  thetao
  uo
  vo
  zos
  siconc
)
read -r -a VARS <<< "${VARS:-${VARS_DEFAULT[*]}}"
EXCLUDE_NODES="${EXCLUDE_NODES:-}"
CLIMATOLOGY_MODE="${CLIMATOLOGY_MODE:-whole}"
MEM_3D="${MEM_3D:-128G}"
MEM_2D="${MEM_2D:-32G}"
WALLTIME="${WALLTIME:-7-00:00:00}"
CLIM_SCRATCH_ROOT="${CLIM_SCRATCH_ROOT:-}"
CLIM_SCRATCH_POLICY="${CLIM_SCRATCH_POLICY:-per_month}"
CLIM_REUSE_MONTHS="${CLIM_REUSE_MONTHS:-}"
if [[ -n "$CLIM_SCRATCH_ROOT" ]]; then
  CLIM_WORKERS="${CLIM_WORKERS:-1}"
fi

VARS_2D=(
  mlotst
  zos
  siconc
)

if [[ "$CLIM_SCRATCH_POLICY" != per_month && "$CLIM_SCRATCH_POLICY" != shared ]]; then
  echo "ERROR: CLIM_SCRATCH_POLICY must be per_month or shared" >&2
  exit 1
fi
if [[ "$CLIM_SCRATCH_POLICY" == shared && ( -z "$CLIM_SCRATCH_ROOT" || "$CLIMATOLOGY_MODE" == whole ) ]]; then
  echo "ERROR: Shared scratch requires CLIM_SCRATCH_ROOT and monthly or seasonal mode" >&2
  exit 1
fi

if [[ "$CLIMATOLOGY_MODE" != "whole" && "$CLIMATOLOGY_MODE" != "monthly" && "$CLIMATOLOGY_MODE" != "seasonal" ]]; then
  echo "ERROR: CLIMATOLOGY_MODE must be one of: whole, monthly, seasonal" >&2
  exit 1
fi
if [[ -n "$CLIM_SCRATCH_ROOT" && "$CLIM_SCRATCH_POLICY" != shared && ( "$CLIMATOLOGY_MODE" != monthly || "$CLIM_WORKERS" != 1 ) ]]; then
  echo "ERROR: Scratch staging requires CLIMATOLOGY_MODE=monthly and CLIM_WORKERS=1" >&2
  exit 1
fi

make_sbatch_extra_args() {
  if [[ -n "$EXCLUDE_NODES" ]]; then
    printf '%s\n' "--exclude=${EXCLUDE_NODES}"
  fi
}

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="glorys12v1"
INROOT_BASE="/home/SB5/reanalysis/glorys12v1/monthly_0p05"
WINDOW_START="200601"
WINDOW_END="201412"
EXPECTED_N=108

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

SUBMISSION_LOG="${SUBMISSION_LOG:-/home/sandbox-sparc/cesmle-ocn-fetch/logs/climatology_submissions.tsv}"
mkdir -p "$(dirname "$SUBMISSION_LOG")"
record_submission() {
  # Columns: UTC submission time, job ID, dataset label, variable, window, mode.
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$4" "$CLIMATOLOGY_MODE" >> "$SUBMISSION_LOG"
}
echo "Submission receipts: $SUBMISSION_LOG"


echo "Submitting GLORYS climatology window jobs with generic worker:"
echo "  mode: ${CLIMATOLOGY_MODE}"
echo "  scratch: ${CLIM_SCRATCH_ROOT:-<disabled>}"
for v in "${VARS[@]}"; do
  IN_DIR="${INROOT_BASE}/${v}/parts"
  OUT_SUBDIR="clim_windows"
  if [[ "$CLIMATOLOGY_MODE" == "monthly" ]]; then
    OUT_SUBDIR="clim_monthly"
  elif [[ "$CLIMATOLOGY_MODE" == "seasonal" ]]; then
    OUT_SUBDIR="clim_seasonal"
  fi
  OUT_DIR="${INROOT_BASE}/${v}/${OUT_SUBDIR}"
  TMP_DIR="${INROOT_BASE}/${v}/tmp_clim"

  JOB_MEMORY="$MEM_3D"
  if [[ " ${VARS_2D[*]} " == *" ${v} "* ]]; then
    JOB_MEMORY="$MEM_2D"
  fi

  if [[ ! -d "$IN_DIR" ]]; then
    echo "WARN: Input directory not found, skipping: $IN_DIR"
    continue
  fi

  mapfile -t sbatch_extra_args < <(make_sbatch_extra_args)
  echo "  submitting VAR=${v} WINDOW=${WINDOW_START}-${WINDOW_END}"
  jid=$(DATASET_LABEL="$DATASET_LABEL" \
    VAR="$v" \
    IN_DIR="$IN_DIR" \
    OUT_DIR="$OUT_DIR" \
    TMP_DIR="$TMP_DIR" \
    FILE_GLOB="*.nc" \
    WINDOW_START="$WINDOW_START" \
    WINDOW_END="$WINDOW_END" \
    EXPECTED_N="$EXPECTED_N" \
    CLIMATOLOGY_MODE="$CLIMATOLOGY_MODE" \
    CLIM_SCRATCH_ROOT="$CLIM_SCRATCH_ROOT" \
    CLIM_SCRATCH_POLICY="$CLIM_SCRATCH_POLICY" \
    CLIM_REUSE_MONTHS="$CLIM_REUSE_MONTHS" \
    OUT_PREFIX="${DATASET_LABEL}_${v}" \
    sbatch --parsable \
    "${sbatch_extra_args[@]}" \
    --job-name="gclim_${v}" \
    --mem="$JOB_MEMORY" \
    --time="$WALLTIME" \
    "$CORE_SCRIPT")
  record_submission "$jid" "$DATASET_LABEL" "$v" "${WINDOW_START}-${WINDOW_END}"
  echo "  submitted VAR=${v} MEMORY=${JOB_MEMORY} as jobid=${jid}"
done

echo "Done. Submission receipts: $SUBMISSION_LOG"
