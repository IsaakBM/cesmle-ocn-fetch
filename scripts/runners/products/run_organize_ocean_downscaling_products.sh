#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling product tree organization
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit the copy-only curated product builder as multiple subtree jobs.
#
# Notes:
#   - This does NOT move or delete source data.
#   - It builds / refreshes:
#       /home/SB5/ocean_downscaling_products/
#   - It fans out by curated subtree and lets each worker copy files with
#     modest internal parallelism.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/organize_ocean_downscaling_products.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
MEMORY="${MEMORY:-64G}"
WALLTIME="${WALLTIME:-2-00:00:00}"
NPROC="${NPROC:-${CPUS_PER_TASK}}"
MODEL="${MODEL:-auto}"
REALIZATION="${REALIZATION:-auto}"
SCENARIO="${SCENARIO:-auto}"
PRODUCT_ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
HINDCAST_0P25_ROOT="${HINDCAST_0P25_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25}"
HINDCAST_0P05_ROOT="${HINDCAST_0P05_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast}"
HINDCAST_0P05_COASTAL_FILLED_ROOT="${HINDCAST_0P05_COASTAL_FILLED_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_coastal_filled}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/glorys12v1_monthly_0p05}"
DOWNSCALED_ROOT="${DOWNSCALED_ROOT:-/home/SB5/downscaled}"
CESM_LEGACY_DOWNSCALED_ROOT="${CESM_LEGACY_DOWNSCALED_ROOT:-/home/SB5/downscaled_rcp85}"
OVERWRITE="${OVERWRITE:-no}"
USE_COASTAL_FILLED_BASELINE="${USE_COASTAL_FILLED_BASELINE:-no}"
COASTAL_FILLED_BASELINE_VARS="${COASTAL_FILLED_BASELINE_VARS:-chl o2}"
ORGANIZE_SCOPES="${ORGANIZE_SCOPES:-baseline future}"
VARS="${VARS:-thetao so ph o2 chl uo vo zooc zos mlotst siconc}"
BASELINE_VARS="${BASELINE_VARS:-chl o2 ph thetao so uo vo zos mlotst siconc}"
WINDOWS="${WINDOWS:-2030-2060 2050-2060 2090-2100}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

read -r -a SCOPE_LIST <<< "${ORGANIZE_SCOPES}"
read -r -a VAR_LIST <<< "${VARS}"
read -r -a BASELINE_VAR_LIST <<< "${BASELINE_VARS}"
read -r -a WINDOW_LIST <<< "${WINDOWS}"

declare -a TASKS=()
for scope in "${SCOPE_LIST[@]}"; do
  case "${scope}" in
    baseline)
      for var in "${BASELINE_VAR_LIST[@]}"; do
        TASKS+=("baseline ${var}")
      done
      ;;
    future)
      for var in "${VAR_LIST[@]}"; do
        for window in "${WINDOW_LIST[@]}"; do
          TASKS+=("future ${var} ${window}")
        done
      done
      ;;
    *)
      echo "ERROR: ORGANIZE_SCOPES entries must be baseline or future: ${scope}"
      exit 1
      ;;
  esac
done

echo "ORGANIZE SCOPES : ${SCOPE_LIST[*]}"
echo "VARS            : ${VAR_LIST[*]}"
echo "BASELINE VARS   : ${BASELINE_VAR_LIST[*]}"
echo "WINDOWS         : ${WINDOW_LIST[*]}"
echo "MODEL           : ${MODEL}"
echo "REALIZATION     : ${REALIZATION}"
echo "SCENARIO        : ${SCENARIO}"
echo "PRODUCT ROOT    : ${PRODUCT_ROOT}"
echo "DOWNSCALED ROOT : ${DOWNSCALED_ROOT}"
echo "OVERWRITE       : ${OVERWRITE}"
echo

echo "Submitting curated ocean product organization jobs by subtree:"
for task in "${TASKS[@]}"; do
  read -r scope var window <<<"${task}"
  job_tag="${scope}_${var}"
  wrap_cmd="ORGANIZE_SCOPE='${scope}' VAR='${var}' NPROC='${NPROC}' MODEL='${MODEL}' REALIZATION='${REALIZATION}' SCENARIO='${SCENARIO}' PRODUCT_ROOT='${PRODUCT_ROOT}' HINDCAST_0P25_ROOT='${HINDCAST_0P25_ROOT}' HINDCAST_0P05_ROOT='${HINDCAST_0P05_ROOT}' HINDCAST_0P05_COASTAL_FILLED_ROOT='${HINDCAST_0P05_COASTAL_FILLED_ROOT}' GLORYS_ROOT='${GLORYS_ROOT}' DOWNSCALED_ROOT='${DOWNSCALED_ROOT}' CESM_LEGACY_DOWNSCALED_ROOT='${CESM_LEGACY_DOWNSCALED_ROOT}' USE_COASTAL_FILLED_BASELINE='${USE_COASTAL_FILLED_BASELINE}' COASTAL_FILLED_BASELINE_VARS='${COASTAL_FILLED_BASELINE_VARS}' BASELINE_VARS='${BASELINE_VARS}' FUTURE_VARS='${VARS}' WINDOWS='${WINDOWS}' OVERWRITE='${OVERWRITE}'"
  if [[ "${scope}" == "future" ]]; then
    job_tag="${job_tag}_${window}"
    wrap_cmd="${wrap_cmd} WINDOW='${window}'"
  fi
  wrap_cmd="${wrap_cmd} bash '${TOOL_SCRIPT}'"

  jid=$(
    sbatch --parsable \
      --job-name="organize_${job_tag}" \
      --partition="${PARTITION}" \
      --nodes="${NODES}" \
      --ntasks="${NTASKS}" \
      --cpus-per-task="${CPUS_PER_TASK}" \
      --mem="${MEMORY}" \
      --time="${WALLTIME}" \
      --output="${LOG_DIR}/organize_${job_tag}_%j.out" \
      --error="${LOG_DIR}/organize_${job_tag}_%j.err" \
      --wrap="${wrap_cmd}"
  )
  echo "  submitted SCOPE=${scope} VAR=${var}${window:+ WINDOW=${window}} as jobid=${jid}"
done

echo "Done."
