#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling product tree organization
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit the copy-only curated product builder as a single Slurm job.
#
# Notes:
#   - This does NOT move or delete source data.
#   - It builds / refreshes:
#       /home/SB5/ocean_downscaling_products/
#   - It is intended for offline / background execution because the copy step
#     may take time for the larger CESM downscaled products.
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

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

echo "Submitting curated ocean product organization job:"
jid=$(
  sbatch --parsable \
    --job-name="organize_products" \
    --partition="${PARTITION}" \
    --nodes="${NODES}" \
    --ntasks="${NTASKS}" \
    --cpus-per-task="${CPUS_PER_TASK}" \
    --mem="${MEMORY}" \
    --time="${WALLTIME}" \
    --output="${LOG_DIR}/organize_products_%j.out" \
    --error="${LOG_DIR}/organize_products_%j.err" \
    --wrap="bash '${TOOL_SCRIPT}'"
)

echo "  submitted as jobid=${jid}"
echo "Done."
