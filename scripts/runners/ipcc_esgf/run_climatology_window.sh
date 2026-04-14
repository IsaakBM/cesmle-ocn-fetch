#!/usr/bin/env bash
# ==============================================================================
#  IPCC ESGF runner for generic climatology window builder from time-series files
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit climatology window jobs for selected scenario(s) and variable(s)
# using the generic climatology builder for time-series files.
#
# Notes:
#   - This runner is intended for already-monthly ESGF/IPCC time-series files
#     already harmonized to a common 1 x 1 degree grid.
#   - Expected input layout:
#       /home/SB5/ipcc_esgf_monthly_1deg/<scenario>/<variable>/parts/*.nc
#   - Historical is typically one long file.
#   - SSP585 may contain multiple time chunks, which are merged automatically
#     before the climatology window is selected and averaged.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/climatology_window_from_timeseries.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
SCENARIOS=(
  historical
  ssp585
)

VARS=(
  chl
  o2
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="ipcc_esgf"
INROOT_BASE="/home/SB5/ipcc_esgf_monthly_1deg"

# Historical baseline window
HIST_WINDOW_START="2006-01-01"
HIST_WINDOW_END="2014-12-31"

# Future scenario windows
FUT2050_WINDOW_START="2050-01-01"
FUT2050_WINDOW_END="2060-12-31"
FUT2090_WINDOW_START="2090-01-01"
FUT2090_WINDOW_END="2100-12-31"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting IPCC/ESGF climatology window jobs with generic worker:"
for scen in "${SCENARIOS[@]}"; do
  echo "Scenario: $scen"
  for v in "${VARS[@]}"; do
    IN_DIR="${INROOT_BASE}/${scen}/${v}/parts"
    OUT_DIR="${INROOT_BASE}/${scen}/${v}/clim_windows"
    TMP_DIR="${INROOT_BASE}/${scen}/${v}/tmp_clim"

    if [[ ! -d "$IN_DIR" ]]; then
      echo "  WARN: Input directory not found, skipping: $IN_DIR"
      continue
    fi

    if [[ "$scen" == "historical" ]]; then
      jid=$(DATASET_LABEL="${DATASET_LABEL}_${scen}" \
        VAR="$v" \
        IN_DIR="$IN_DIR" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FILE_GLOB="*.nc" \
        WINDOW_START="$HIST_WINDOW_START" \
        WINDOW_END="$HIST_WINDOW_END" \
        MERGE_INPUTS="auto" \
        OUT_PREFIX="${DATASET_LABEL}_${scen}_${v}" \
        sbatch --parsable \
        --job-name="clim_${scen}_${v}" \
        "$CORE_SCRIPT")
      echo "  submitted SCENARIO=${scen} VAR=${v} WINDOW=baseline as jobid=${jid}"
    else
      jid2050=$(DATASET_LABEL="${DATASET_LABEL}_${scen}" \
        VAR="$v" \
        IN_DIR="$IN_DIR" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FILE_GLOB="*.nc" \
        WINDOW_START="$FUT2050_WINDOW_START" \
        WINDOW_END="$FUT2050_WINDOW_END" \
        MERGE_INPUTS="auto" \
        OUT_PREFIX="${DATASET_LABEL}_${scen}_${v}" \
        sbatch --parsable \
        --job-name="clim2050_${v}" \
        "$CORE_SCRIPT")
      echo "  submitted SCENARIO=${scen} VAR=${v} WINDOW=2050-2060 as jobid=${jid2050}"

      jid2090=$(DATASET_LABEL="${DATASET_LABEL}_${scen}" \
        VAR="$v" \
        IN_DIR="$IN_DIR" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FILE_GLOB="*.nc" \
        WINDOW_START="$FUT2090_WINDOW_START" \
        WINDOW_END="$FUT2090_WINDOW_END" \
        MERGE_INPUTS="auto" \
        OUT_PREFIX="${DATASET_LABEL}_${scen}_${v}" \
        sbatch --parsable \
        --job-name="clim2090_${v}" \
        "$CORE_SCRIPT")
      echo "  submitted SCENARIO=${scen} VAR=${v} WINDOW=2090-2100 as jobid=${jid2090}"
    fi
  done
done

echo "Done."
