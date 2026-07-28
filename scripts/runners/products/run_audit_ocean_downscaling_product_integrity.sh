#!/usr/bin/env bash
# ==============================================================================
#  Slurm runner for curated ocean product integrity audit
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/audit_ocean_downscaling_product_integrity.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-2}"
MEMORY="${MEMORY:-16G}"
WALLTIME="${WALLTIME:-5-00:00:00}"
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"

PRODUCT_ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
OUT_FILE="${OUT_FILE:-data/manifests/ocean_downscaling_product_integrity_audit.csv}"
FUTURE_MODELS="${FUTURE_MODELS:-auto}"
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS:-cesm_f09_g16 legacy_downscaled_rcp85}"
SCENARIOS="${SCENARIOS:-auto}"
VARS="${VARS:-auto}"
WINDOWS="${WINDOWS:-auto}"
RESOLUTIONS="${RESOLUTIONS:-auto}"
INCLUDE_BASELINE="${INCLUDE_BASELINE:-yes}"
INCLUDE_FUTURE="${INCLUDE_FUTURE:-yes}"
COMPUTE_STATS="${COMPUTE_STATS:-no}"
FAIL_ON_ISSUE="${FAIL_ON_ISSUE:-no}"

mkdir -p "${LOG_DIR}" "$(dirname "${OUT_FILE}")"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}" >&2
  exit 1
fi

echo "Submitting ocean product integrity audit:"
echo "PRODUCT ROOT    : ${PRODUCT_ROOT}"
echo "OUT FILE        : ${OUT_FILE}"
echo "FUTURE MODELS   : ${FUTURE_MODELS}"
echo "EXCLUDE FUTURE  : ${EXCLUDE_FUTURE_MODELS:-<none>}"
echo "SCENARIOS       : ${SCENARIOS}"
echo "VARS            : ${VARS}"
echo "WINDOWS         : ${WINDOWS}"
echo "RESOLUTIONS     : ${RESOLUTIONS}"
echo "INCLUDE BASE    : ${INCLUDE_BASELINE}"
echo "INCLUDE FUTURE  : ${INCLUDE_FUTURE}"
echo "COMPUTE STATS   : ${COMPUTE_STATS}"
echo "FAIL ON ISSUE   : ${FAIL_ON_ISSUE}"
echo "EXCLUDE NODES   : ${EXCLUDE_NODES:-<none>}"

sbatch_args=()
if [[ -n "${EXCLUDE_NODES}" ]]; then
  sbatch_args+=(--exclude="${EXCLUDE_NODES}")
fi

jid=$(
  sbatch --parsable \
    --job-name="audit_product_integrity" \
    --partition="${PARTITION}" \
    --nodes="${NODES}" \
    --ntasks="${NTASKS}" \
    --cpus-per-task="${CPUS_PER_TASK}" \
    --mem="${MEMORY}" \
    --time="${WALLTIME}" \
    "${sbatch_args[@]}" \
    --output="${LOG_DIR}/audit_product_integrity_%j.out" \
    --error="${LOG_DIR}/audit_product_integrity_%j.err" \
    --export=ALL,PRODUCT_ROOT="${PRODUCT_ROOT}",OUT_FILE="${OUT_FILE}",FUTURE_MODELS="${FUTURE_MODELS}",EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS}",SCENARIOS="${SCENARIOS}",VARS="${VARS}",WINDOWS="${WINDOWS}",RESOLUTIONS="${RESOLUTIONS}",INCLUDE_BASELINE="${INCLUDE_BASELINE}",INCLUDE_FUTURE="${INCLUDE_FUTURE}",COMPUTE_STATS="${COMPUTE_STATS}",FAIL_ON_ISSUE="${FAIL_ON_ISSUE}" \
    "${TOOL_SCRIPT}"
)

echo "Submitted batch job ${jid}"
