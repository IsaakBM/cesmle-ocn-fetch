#!/usr/bin/env bash
# ==============================================================================
#  Slurm runner for curated ocean product value audit
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/audit_ocean_downscaling_product_values.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-2}"
MEMORY="${MEMORY:-16G}"
WALLTIME="${WALLTIME:-5-00:00:00}"
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"

PRODUCT_ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
OUT_FILE="${OUT_FILE:-data/manifests/future_product_value_audit_0p05.csv}"
FUTURE_MODELS="${FUTURE_MODELS:-auto}"
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS:-cesm_f09_g16 legacy_downscaled_rcp85}"
SCENARIOS="${SCENARIOS:-auto}"
VARS="${VARS:-auto}"
WINDOWS="${WINDOWS:-auto}"
RESOLUTIONS="${RESOLUTIONS:-0p05}"
INCLUDE_ENSEMBLE="${INCLUDE_ENSEMBLE:-yes}"
MAX_FILES="${MAX_FILES:-}"
PROGRESS_EVERY="${PROGRESS_EVERY:-1}"

mkdir -p "${LOG_DIR}" "$(dirname "${OUT_FILE}")"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}" >&2
  exit 1
fi

echo "Submitting ocean product value audit:"
echo "PRODUCT ROOT    : ${PRODUCT_ROOT}"
echo "OUT FILE        : ${OUT_FILE}"
echo "FUTURE MODELS   : ${FUTURE_MODELS}"
echo "EXCLUDE FUTURE  : ${EXCLUDE_FUTURE_MODELS:-<none>}"
echo "SCENARIOS       : ${SCENARIOS}"
echo "VARS            : ${VARS}"
echo "WINDOWS         : ${WINDOWS}"
echo "RESOLUTIONS     : ${RESOLUTIONS}"
echo "INCLUDE ENS     : ${INCLUDE_ENSEMBLE}"
echo "MAX FILES       : ${MAX_FILES:-<none>}"
echo "PROGRESS EVERY  : ${PROGRESS_EVERY}"
echo "EXCLUDE NODES   : ${EXCLUDE_NODES:-<none>}"

sbatch_args=()
if [[ -n "${EXCLUDE_NODES}" ]]; then
  sbatch_args+=(--exclude="${EXCLUDE_NODES}")
fi

jid=$(
  sbatch --parsable \
    --job-name="audit_future_values" \
    --partition="${PARTITION}" \
    --nodes="${NODES}" \
    --ntasks="${NTASKS}" \
    --cpus-per-task="${CPUS_PER_TASK}" \
    --mem="${MEMORY}" \
    --time="${WALLTIME}" \
    "${sbatch_args[@]}" \
    --output="${LOG_DIR}/audit_future_values_%j.out" \
    --error="${LOG_DIR}/audit_future_values_%j.err" \
    --export=ALL,PRODUCT_ROOT="${PRODUCT_ROOT}",OUT_FILE="${OUT_FILE}",FUTURE_MODELS="${FUTURE_MODELS}",EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS}",SCENARIOS="${SCENARIOS}",VARS="${VARS}",WINDOWS="${WINDOWS}",RESOLUTIONS="${RESOLUTIONS}",INCLUDE_ENSEMBLE="${INCLUDE_ENSEMBLE}",MAX_FILES="${MAX_FILES}",PROGRESS_EVERY="${PROGRESS_EVERY}" \
    "${TOOL_SCRIPT}"
)

echo "Submitted batch job ${jid}"
