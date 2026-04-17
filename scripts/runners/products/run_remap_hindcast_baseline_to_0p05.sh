#!/usr/bin/env bash
# ==============================================================================
#  Runner for deriving hindcast baseline climatologies at 0.05 degree
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/remap_hindcast_baseline_to_0p05.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
MEMORY="${MEMORY:-256G}"
WALLTIME="${WALLTIME:-2-00:00:00}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

echo "Submitting hindcast baseline 0.25 -> 0.05 remap job:"
jid=$(
  sbatch --parsable \
    --job-name="hindcast_0p05" \
    --partition="${PARTITION}" \
    --nodes="${NODES}" \
    --ntasks="${NTASKS}" \
    --cpus-per-task="${CPUS_PER_TASK}" \
    --mem="${MEMORY}" \
    --time="${WALLTIME}" \
    --output="${LOG_DIR}/hindcast_0p05_%j.out" \
    --error="${LOG_DIR}/hindcast_0p05_%j.err" \
    --wrap="bash '${TOOL_SCRIPT}'"
)

echo "  submitted as jobid=${jid}"
echo "Done."
