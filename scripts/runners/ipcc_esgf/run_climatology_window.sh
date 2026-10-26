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
#     already harmonized to a common 1 x 1 degree grid and vertically
#     interpolated to GLORYS levels for 3D variables.
#   - Expected input layout:
#       /home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<scenario>/<variable>/on_glorys/*.nc
#     for 3D variables, and:
#       /home/SB5/ipcc_esgf/monthly_1deg/<model>/<member>/<scenario>/<variable>/parts/*.nc
#     for 2D variables.
#   - Historical is typically one long file.
#   - SSP585 may contain multiple time chunks, which are merged automatically
#     before the climatology window is selected and averaged.
#   - Whole-window behavior remains the default; monthly and seasonal products
#     are explicit CLIMATOLOGY_MODE options.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/climatology_window_from_timeseries.slurm.sh"
DISCOVERY_LIB="${SCRIPT_DIR}/../../lib/ipcc_esgf_discovery.sh"

# shellcheck source=../../lib/ipcc_esgf_discovery.sh
source "${DISCOVERY_LIB}"

VARS_DEFAULT=(
  thetao
  so
  ph
  o2
  chl
  uo
  vo
  zooc
  zos
  mlotst
  siconc
)
read -r -a VARS <<< "${VARS:-${VARS_DEFAULT[*]}}"
read -r -a MODELS <<< "${MODELS:-}"
read -r -a SCENARIOS <<< "${SCENARIOS:-}"
read -r -a WINDOWS <<< "${WINDOWS:-}"
EXCLUDE_NODES="${EXCLUDE_NODES:-}"
CLIMATOLOGY_MODE="${CLIMATOLOGY_MODE:-whole}"
CLIM_SCRATCH_POLICY="${CLIM_SCRATCH_POLICY:-per_month}"
CLIM_SCRATCH_ROOT="${CLIM_SCRATCH_ROOT:-}"
CLIM_SCRATCH_HEADROOM_GB="${CLIM_SCRATCH_HEADROOM_GB:-10}"
MEM_3D="${MEM_3D:-8G}"
MEM_2D="${MEM_2D:-4G}"
WALLTIME="${WALLTIME:-7-00:00:00}"

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

contains_filter_value() {
  local value="$1"
  shift

  if (( $# == 0 )); then
    return 0
  fi

  local allowed
  for allowed in "$@"; do
    if [[ "$value" == "$allowed" ]]; then
      return 0
    fi
  done

  return 1
}

make_sbatch_extra_args() {
  if [[ -n "$EXCLUDE_NODES" ]]; then
    printf '%s\n' "--exclude=${EXCLUDE_NODES}"
  fi
}

VARS_2D=(
  zos
  mlotst
  siconc
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="ipcc_esgf"
IPCC_ESGF_ROOT="${IPCC_ESGF_ROOT:-/home/SB5/ipcc_esgf}"
INROOT_BASE="${INROOT_BASE:-${IPCC_ESGF_ROOT}/monthly_1deg}"
MEMBER="${MEMBER:-auto}"

# Historical baseline window
HIST_WINDOW_START="2006-01-01"
HIST_WINDOW_END="2014-12-31"

# Future scenario windows
FUT2030_WINDOW_START="2030-01-01"
FUT2030_WINDOW_END="2040-12-31"
FUT2050_WINDOW_START="2050-01-01"
FUT2050_WINDOW_END="2060-12-31"
FUT2090_WINDOW_START="2090-01-01"
FUT2090_WINDOW_END="2100-12-31"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

SUBMISSION_LOG="${SUBMISSION_LOG:-/home/sandbox-sparc/cesmle-ocn-fetch/logs/climatology_submissions.tsv}"
mkdir -p "$(dirname "$SUBMISSION_LOG")"
record_submission() {
  # Columns: UTC submission time, job ID, dataset label, variable, window, mode.
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$4" "$CLIMATOLOGY_MODE" >> "$SUBMISSION_LOG"
}
echo "Submission receipts: $SUBMISSION_LOG"


echo "Submitting IPCC/ESGF climatology window jobs with generic worker:"
echo "  mode: ${CLIMATOLOGY_MODE}"
echo "  discovering requested groups: models=${MODELS[*]:-all} scenarios=${SCENARIOS[*]:-all} vars=${VARS[*]}"
mapfile -t DISCOVERED_GROUPS < <(
  {
    ipcc_esgf_discover_monthly_groups_any_layout "${INROOT_BASE}" "on_glorys" "${MODELS[*]}" "${SCENARIOS[*]}" "${VARS[*]}" "$MEMBER"
    ipcc_esgf_discover_monthly_groups_any_layout "${INROOT_BASE}" "parts" "${MODELS[*]}" "${SCENARIOS[*]}" "${VARS[*]}" "$MEMBER"
  } | sort -u
)

if (( ${#DISCOVERED_GROUPS[@]} == 0 )); then
  echo "ERROR: No model/member/scenario/variable monthly directories discovered under: ${INROOT_BASE}"
  exit 1
fi

echo "  discovery complete: ${#DISCOVERED_GROUPS[@]} candidate groups"

for group in "${DISCOVERED_GROUPS[@]}"; do
  IFS=$'\t' read -r model member scen v <<< "$group"

  if [[ ! " ${VARS[*]} " == *" ${v} "* ]]; then
    continue
  fi

  if ! contains_filter_value "$model" "${MODELS[@]}"; then
    continue
  fi

  if ! contains_filter_value "$scen" "${SCENARIOS[@]}"; then
    continue
  fi

  if [[ "${MEMBER}" != "auto" && "${member}" != "${MEMBER}" ]]; then
    continue
  fi

  echo "  checking MODEL=${model} MEMBER=${member} SCENARIO=${scen} VAR=${v}"
  source_subdir="on_glorys"
  if [[ " ${VARS_2D[*]} " == *" ${v} "* ]]; then
    source_subdir="parts"
  fi

  if ! IN_DIR="$(ipcc_esgf_monthly_stage_dir_for_group "$INROOT_BASE" "$model" "$member" "$scen" "$v" "$source_subdir")"; then
    echo "  WARN: ${source_subdir} input not found, skipping MODEL=${model} MEMBER=${member} SCENARIO=${scen} VAR=${v}"
    continue
  fi

  VAR_DIR="$(ipcc_esgf_monthly_var_dir_for_group "$INROOT_BASE" "$model" "$member" "$scen" "$v")"
  OUT_SUBDIR="clim_windows"
  if [[ "$CLIMATOLOGY_MODE" == "monthly" ]]; then
    OUT_SUBDIR="clim_monthly"
  elif [[ "$CLIMATOLOGY_MODE" == "seasonal" ]]; then
    OUT_SUBDIR="clim_seasonal"
  fi
  OUT_DIR="${VAR_DIR}/${OUT_SUBDIR}"
  TMP_DIR="${VAR_DIR}/tmp_clim"
  file_glob="${v}_*_${model}_${scen}_*.nc"
  JOB_MEMORY="$MEM_3D"
  if [[ " ${VARS_2D[*]} " == *" ${v} "* ]]; then
    JOB_MEMORY="$MEM_2D"
  fi

  member="$(MEMBER="$member" ipcc_esgf_resolve_member "$IN_DIR" "$file_glob")" || {
    status=$?
    [[ "$status" -eq 2 ]] && continue
    exit "$status"
  }

  file_glob="${v}_*_${model}_${scen}_${member}_*.nc"
  out_prefix="${DATASET_LABEL}_${model}_${scen}_${member}_${v}"
  mapfile -t sbatch_extra_args < <(make_sbatch_extra_args)

  if [[ "$scen" == "historical" ]]; then
    if contains_filter_value "baseline" "${WINDOWS[@]}"; then
      echo "  submitting MODEL=${model} SCENARIO=${scen} VAR=${v} WINDOW=baseline"
      jid=$(DATASET_LABEL="${DATASET_LABEL}_${model}_${scen}_${member}" \
        VAR="$v" \
        IN_DIR="$IN_DIR" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FILE_GLOB="$file_glob" \
        WINDOW_START="$HIST_WINDOW_START" \
        WINDOW_END="$HIST_WINDOW_END" \
        MERGE_INPUTS="auto" \
        CLIMATOLOGY_MODE="$CLIMATOLOGY_MODE" \
        CLIM_SCRATCH_POLICY="$CLIM_SCRATCH_POLICY" \
        CLIM_SCRATCH_ROOT="$CLIM_SCRATCH_ROOT" \
        CLIM_SCRATCH_HEADROOM_GB="$CLIM_SCRATCH_HEADROOM_GB" \
        OUT_PREFIX="$out_prefix" \
        sbatch --parsable \
        "${sbatch_extra_args[@]}" \
        --job-name="clim_${scen}_${v}" \
        --mem="$JOB_MEMORY" \
        --time="$WALLTIME" \
        "$CORE_SCRIPT")
      record_submission "${jid}" "${DATASET_LABEL}_${model}_${scen}_${member}" "$v" "baseline"
      echo "  submitted MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v} WINDOW=baseline MEMORY=${JOB_MEMORY} as jobid=${jid}"
    fi
  else
    if contains_filter_value "2030-2040" "${WINDOWS[@]}"; then
      echo "  submitting MODEL=${model} SCENARIO=${scen} VAR=${v} WINDOW=2030"
      jid2030=$(DATASET_LABEL="${DATASET_LABEL}_${model}_${scen}_${member}" \
        VAR="$v" \
        IN_DIR="$IN_DIR" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FILE_GLOB="$file_glob" \
        WINDOW_START="$FUT2030_WINDOW_START" \
        WINDOW_END="$FUT2030_WINDOW_END" \
        MERGE_INPUTS="auto" \
        CLIMATOLOGY_MODE="$CLIMATOLOGY_MODE" \
        CLIM_SCRATCH_POLICY="$CLIM_SCRATCH_POLICY" \
        CLIM_SCRATCH_ROOT="$CLIM_SCRATCH_ROOT" \
        CLIM_SCRATCH_HEADROOM_GB="$CLIM_SCRATCH_HEADROOM_GB" \
        OUT_PREFIX="$out_prefix" \
        sbatch --parsable \
        "${sbatch_extra_args[@]}" \
        --job-name="clim2030_${v}" \
        --mem="$JOB_MEMORY" \
        --time="$WALLTIME" \
        "$CORE_SCRIPT")
      record_submission "${jid2030}" "${DATASET_LABEL}_${model}_${scen}_${member}" "$v" "2030-2040"
      echo "  submitted MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v} WINDOW=2030-2040 MEMORY=${JOB_MEMORY} as jobid=${jid2030}"
    fi

    if contains_filter_value "2050-2060" "${WINDOWS[@]}"; then
      echo "  submitting MODEL=${model} SCENARIO=${scen} VAR=${v} WINDOW=2050"
      jid2050=$(DATASET_LABEL="${DATASET_LABEL}_${model}_${scen}_${member}" \
        VAR="$v" \
        IN_DIR="$IN_DIR" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FILE_GLOB="$file_glob" \
        WINDOW_START="$FUT2050_WINDOW_START" \
        WINDOW_END="$FUT2050_WINDOW_END" \
        MERGE_INPUTS="auto" \
        CLIMATOLOGY_MODE="$CLIMATOLOGY_MODE" \
        CLIM_SCRATCH_POLICY="$CLIM_SCRATCH_POLICY" \
        CLIM_SCRATCH_ROOT="$CLIM_SCRATCH_ROOT" \
        CLIM_SCRATCH_HEADROOM_GB="$CLIM_SCRATCH_HEADROOM_GB" \
        OUT_PREFIX="$out_prefix" \
        sbatch --parsable \
        "${sbatch_extra_args[@]}" \
        --job-name="clim2050_${v}" \
        --mem="$JOB_MEMORY" \
        --time="$WALLTIME" \
        "$CORE_SCRIPT")
      record_submission "${jid2050}" "${DATASET_LABEL}_${model}_${scen}_${member}" "$v" "2050-2060"
      echo "  submitted MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v} WINDOW=2050-2060 MEMORY=${JOB_MEMORY} as jobid=${jid2050}"
    fi

    if contains_filter_value "2090-2100" "${WINDOWS[@]}"; then
      echo "  submitting MODEL=${model} SCENARIO=${scen} VAR=${v} WINDOW=2090"
      jid2090=$(DATASET_LABEL="${DATASET_LABEL}_${model}_${scen}_${member}" \
        VAR="$v" \
        IN_DIR="$IN_DIR" \
        OUT_DIR="$OUT_DIR" \
        TMP_DIR="$TMP_DIR" \
        FILE_GLOB="$file_glob" \
        WINDOW_START="$FUT2090_WINDOW_START" \
        WINDOW_END="$FUT2090_WINDOW_END" \
        MERGE_INPUTS="auto" \
        CLIMATOLOGY_MODE="$CLIMATOLOGY_MODE" \
        CLIM_SCRATCH_POLICY="$CLIM_SCRATCH_POLICY" \
        CLIM_SCRATCH_ROOT="$CLIM_SCRATCH_ROOT" \
        CLIM_SCRATCH_HEADROOM_GB="$CLIM_SCRATCH_HEADROOM_GB" \
        OUT_PREFIX="$out_prefix" \
        sbatch --parsable \
        "${sbatch_extra_args[@]}" \
        --job-name="clim2090_${v}" \
        --mem="$JOB_MEMORY" \
        --time="$WALLTIME" \
        "$CORE_SCRIPT")
      record_submission "${jid2090}" "${DATASET_LABEL}_${model}_${scen}_${member}" "$v" "2090-2100"
      echo "  submitted MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v} WINDOW=2090-2100 MEMORY=${JOB_MEMORY} as jobid=${jid2090}"
    fi
  fi
done

echo "Done. Submission receipts: $SUBMISSION_LOG"
