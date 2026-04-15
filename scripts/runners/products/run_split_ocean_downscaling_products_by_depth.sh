#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling product splitting by depth
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit the by-depth splitter as a single Slurm job.
#
# Notes:
#   - This mirrors /home/SB5/ocean_downscaling_products into:
#       /home/SB5/ocean_downscaling_products_bydepth
#   - The main tool script carries the HPC resource requests.
#   - This runner remains lightweight and only handles submission/logging.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/split_ocean_downscaling_products_by_depth.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

echo "Submitting curated ocean product by-depth split job:"
jid=$(
  sbatch --parsable "${TOOL_SCRIPT}"
)

echo "  submitted as jobid=${jid}"
echo "Done."
