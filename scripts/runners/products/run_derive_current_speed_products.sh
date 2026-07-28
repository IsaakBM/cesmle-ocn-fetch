#!/usr/bin/env bash
# ==============================================================================
#  Runner for derived sea-water current speed products
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/derive_current_speed_products.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
MEMORY="${MEMORY:-64G}"
WALLTIME="${WALLTIME:-1-00:00:00}"
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"

PRODUCT_ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
DERIVE_SCOPES="${DERIVE_SCOPES:-baseline future}"
SCENARIOS="${SCENARIOS:-ssp126 ssp245 ssp585}"
WINDOWS="${WINDOWS:-2030-2060 2050-2060 2090-2100}"
RESOLUTIONS="${RESOLUTIONS:-0p05}"
MODELS="${MODELS:-auto}"
EXCLUDE_MODELS="${EXCLUDE_MODELS:-cesm_f09_g16 legacy_downscaled_rcp85 ensemble}"
OVERWRITE="${OVERWRITE:-no}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}" >&2
  exit 1
fi

read -r -a SCOPE_LIST <<< "${DERIVE_SCOPES}"
read -r -a SCENARIO_LIST <<< "${SCENARIOS}"
read -r -a WINDOW_LIST <<< "${WINDOWS}"

echo "Submitting derived current_speed jobs:"
echo "PRODUCT ROOT   : ${PRODUCT_ROOT}"
echo "SCOPES         : ${SCOPE_LIST[*]}"
echo "SCENARIOS      : ${SCENARIO_LIST[*]}"
echo "WINDOWS        : ${WINDOW_LIST[*]}"
echo "RESOLUTIONS    : ${RESOLUTIONS}"
echo "MODELS         : ${MODELS}"
echo "EXCLUDE MODELS : ${EXCLUDE_MODELS}"
echo "OVERWRITE      : ${OVERWRITE}"
echo "EXCLUDE NODES  : ${EXCLUDE_NODES:-<none>}"
echo

submit_job() {
  local scope="$1"
  local scenario="$2"
  local window="$3"
  local job_tag
  local jid
  local sbatch_args=()

  job_tag="$(printf '%s_%s_%s' "${scope}" "${scenario}" "${window}" | tr -cd '[:alnum:]_')"
  if [[ -n "${EXCLUDE_NODES}" ]]; then
    sbatch_args+=(--exclude="${EXCLUDE_NODES}")
  fi

  jid=$(
    sbatch --parsable \
      --job-name="derive_current_${job_tag}" \
      --partition="${PARTITION}" \
      --nodes="${NODES}" \
      --ntasks="${NTASKS}" \
      --cpus-per-task="${CPUS_PER_TASK}" \
      --mem="${MEMORY}" \
      --time="${WALLTIME}" \
      "${sbatch_args[@]}" \
      --output="${LOG_DIR}/derive_current_${job_tag}_%j.out" \
      --error="${LOG_DIR}/derive_current_${job_tag}_%j.err" \
      --export=ALL,PRODUCT_ROOT="${PRODUCT_ROOT}",DERIVE_SCOPE="${scope}",SCENARIO="${scenario}",WINDOW="${window}",RESOLUTIONS="${RESOLUTIONS}",MODELS="${MODELS}",EXCLUDE_MODELS="${EXCLUDE_MODELS}",OVERWRITE="${OVERWRITE}" \
      "${TOOL_SCRIPT}"
  )
  echo "  submitted SCOPE=${scope} SCENARIO=${scenario} WINDOW=${window} as jobid=${jid}"
}

for scope in "${SCOPE_LIST[@]}"; do
  case "${scope}" in
    baseline)
      submit_job "baseline" "auto" "auto"
      ;;
    future)
      for scenario in "${SCENARIO_LIST[@]}"; do
        for window in "${WINDOW_LIST[@]}"; do
          submit_job "future" "${scenario}" "${window}"
        done
      done
      ;;
    all)
      submit_job "baseline" "auto" "auto"
      for scenario in "${SCENARIO_LIST[@]}"; do
        for window in "${WINDOW_LIST[@]}"; do
          submit_job "future" "${scenario}" "${window}"
        done
      done
      ;;
    *)
      echo "ERROR: DERIVE_SCOPES entries must be baseline, future, or all: ${scope}" >&2
      exit 1
      ;;
  esac
done

echo "Done."
