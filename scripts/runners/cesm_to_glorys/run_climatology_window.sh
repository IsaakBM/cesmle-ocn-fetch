#!/usr/bin/env bash
# ==============================================================================
#  CESM runner for generic climatology window builder from time-series files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit CESM climatology window jobs per ensemble member using the
# generic climatology worker for time-series files.
#
# Notes:
#   - Uses the rcp85 branch as the continuous 2006-2100 time series.
#   - Merges split member chunks automatically when more than one file matches
#     the member pattern.
#   - Builds exact output prefixes for each member so later stages can target
#     explicit filenames without wildcard matching.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/climatology_window_from_timeseries.slurm.sh"

VARS=(
  TEMP
  SALT
  O2
  UVEL
)

DATASET_LABEL="${DATASET_LABEL:-cesm_rcp85}"
INROOT_BASE="${INROOT_BASE:-/home/SB5/ipcc_esgf/cmip5_rcp85}"

BASE_WINDOW_START="2006-01-01"
BASE_WINDOW_END="2014-12-31"
FUT2050_WINDOW_START="2050-01-01"
FUT2050_WINDOW_END="2060-12-31"
FUT2090_WINDOW_START="2090-01-01"
FUT2090_WINDOW_END="2100-12-31"

member_prefix() {
  local member="$1"
  local var="$2"
  printf 'b.e11.BRCP85C5CNBDRD.f09_g16.%s.pop.h.%s.200601-210012.grid_1deg_pop_global_on_glorys' "$member" "$var"
}

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting CESM climatology window jobs with generic worker:"
for v in "${VARS[@]}"; do
  IN_DIR="${INROOT_BASE}/${v}/on_glorys"
  OUT_DIR="${INROOT_BASE}/${v}/clim_windows"
  TMP_DIR="${INROOT_BASE}/${v}/tmp_clim"

  if [[ ! -d "$IN_DIR" ]]; then
    echo "WARN: Input directory not found, skipping: $IN_DIR"
    continue
  fi

  echo "Variable: ${v}"
  for member_num in $(seq 1 35); do
    member="$(printf '%03d' "${member_num}")"
    member_glob="*f09_g16.${member}.pop.h.${v}*.grid_1deg_pop_global_on_glorys.nc"
    out_prefix="$(member_prefix "${member}" "${v}")"

    jid_base=$(DATASET_LABEL="$DATASET_LABEL" \
      VAR="$v" \
      IN_DIR="$IN_DIR" \
      OUT_DIR="$OUT_DIR" \
      TMP_DIR="$TMP_DIR" \
      FILE_GLOB="$member_glob" \
      WINDOW_START="$BASE_WINDOW_START" \
      WINDOW_END="$BASE_WINDOW_END" \
      MERGE_INPUTS="auto" \
      OUT_PREFIX="$out_prefix" \
      sbatch --parsable \
      --job-name="clim_base_${v}_${member}" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} MEMBER=${member} WINDOW=baseline as jobid=${jid_base}"

    jid2050=$(DATASET_LABEL="$DATASET_LABEL" \
      VAR="$v" \
      IN_DIR="$IN_DIR" \
      OUT_DIR="$OUT_DIR" \
      TMP_DIR="$TMP_DIR" \
      FILE_GLOB="$member_glob" \
      WINDOW_START="$FUT2050_WINDOW_START" \
      WINDOW_END="$FUT2050_WINDOW_END" \
      MERGE_INPUTS="auto" \
      OUT_PREFIX="$out_prefix" \
      sbatch --parsable \
      --job-name="clim2050_${v}_${member}" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} MEMBER=${member} WINDOW=2050-2060 as jobid=${jid2050}"

    jid2090=$(DATASET_LABEL="$DATASET_LABEL" \
      VAR="$v" \
      IN_DIR="$IN_DIR" \
      OUT_DIR="$OUT_DIR" \
      TMP_DIR="$TMP_DIR" \
      FILE_GLOB="$member_glob" \
      WINDOW_START="$FUT2090_WINDOW_START" \
      WINDOW_END="$FUT2090_WINDOW_END" \
      MERGE_INPUTS="auto" \
      OUT_PREFIX="$out_prefix" \
      sbatch --parsable \
      --job-name="clim2090_${v}_${member}" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} MEMBER=${member} WINDOW=2090-2100 as jobid=${jid2090}"
  done
done

echo "Done."
