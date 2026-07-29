#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling model-ensemble products
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/build_ocean_downscaling_ensemble_products.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
MEMORY="${MEMORY:-128G}"
WALLTIME="${WALLTIME:-1-00:00:00}"
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"

PRODUCT_ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
SCENARIOS="${SCENARIOS:-ssp126 ssp245 ssp585}"
VARS="${VARS:-thetao so ph o2 chl uo vo zooc zos mlotst siconc}"
WINDOWS="${WINDOWS:-2030-2040 2050-2060 2090-2100}"
RESOLUTIONS="${RESOLUTIONS:-0p05 0p25}"
MODELS="${MODELS:-auto}"
EXCLUDE_MODELS="${EXCLUDE_MODELS:-cesm_f09_g16 legacy_downscaled_rcp85 ensemble}"
MIN_MODELS="${MIN_MODELS:-2}"
OVERWRITE="${OVERWRITE:-no}"
FILE_INCLUDE_REGEX="${FILE_INCLUDE_REGEX:-}"
VALIDATE_INPUT_TIME="${VALIDATE_INPUT_TIME:-warn}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

if [[ ! -d "${PRODUCT_ROOT}/future" ]]; then
  echo "ERROR: Future product root does not exist: ${PRODUCT_ROOT}/future"
  exit 1
fi

read -r -a SCENARIO_LIST <<< "${SCENARIOS}"
read -r -a VAR_LIST <<< "${VARS}"
read -r -a WINDOW_LIST <<< "${WINDOWS}"
read -r -a RESOLUTION_LIST <<< "${RESOLUTIONS}"

echo "Submitting curated ocean downscaling ensemble jobs:"
echo "PRODUCT ROOT   : ${PRODUCT_ROOT}"
echo "SCENARIOS      : ${SCENARIO_LIST[*]}"
echo "VARS           : ${VAR_LIST[*]}"
echo "WINDOWS        : ${WINDOW_LIST[*]}"
echo "RESOLUTIONS    : ${RESOLUTION_LIST[*]}"
echo "MODELS         : ${MODELS}"
echo "EXCLUDE MODELS : ${EXCLUDE_MODELS}"
echo "MIN MODELS     : ${MIN_MODELS}"
echo "SD METHOD      : CDO ensstd1"
echo "OVERWRITE      : ${OVERWRITE}"
echo "VALIDATE TIME  : ${VALIDATE_INPUT_TIME}"
echo "EXCLUDE NODES  : ${EXCLUDE_NODES:-<none>}"
echo

for scenario in "${SCENARIO_LIST[@]}"; do
  for var in "${VAR_LIST[@]}"; do
    for window in "${WINDOW_LIST[@]}"; do
      for resolution in "${RESOLUTION_LIST[@]}"; do
        job_tag="$(printf '%s_%s_%s_%s' "${scenario}" "${var}" "${window}" "${resolution}" | tr -cd '[:alnum:]_')"
        sbatch_args=()
        if [[ -n "${EXCLUDE_NODES}" ]]; then
          sbatch_args+=(--exclude="${EXCLUDE_NODES}")
        fi
        jid=$(
          sbatch --parsable \
            --job-name="ens_${job_tag}" \
            --partition="${PARTITION}" \
            --nodes="${NODES}" \
            --ntasks="${NTASKS}" \
            --cpus-per-task="${CPUS_PER_TASK}" \
            --mem="${MEMORY}" \
            --time="${WALLTIME}" \
            "${sbatch_args[@]}" \
            --output="${LOG_DIR}/ensemble_${job_tag}_%j.out" \
            --error="${LOG_DIR}/ensemble_${job_tag}_%j.err" \
            --export=ALL,PRODUCT_ROOT="${PRODUCT_ROOT}",SCENARIO="${scenario}",VAR="${var}",WINDOW="${window}",RESOLUTION="${resolution}",MODELS="${MODELS}",EXCLUDE_MODELS="${EXCLUDE_MODELS}",MIN_MODELS="${MIN_MODELS}",OVERWRITE="${OVERWRITE}",FILE_INCLUDE_REGEX="${FILE_INCLUDE_REGEX}",VALIDATE_INPUT_TIME="${VALIDATE_INPUT_TIME}" \
            "${TOOL_SCRIPT}"
        )
        echo "  submitted SCENARIO=${scenario} VAR=${var} WINDOW=${window} RESOLUTION=${resolution} as jobid=${jid}"
      done
    done
  done
done

echo "Done."
