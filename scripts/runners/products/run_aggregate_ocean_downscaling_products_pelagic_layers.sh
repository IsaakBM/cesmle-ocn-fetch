#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling pelagic-layer aggregation
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/aggregate_ocean_downscaling_products_by_depth_bins.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"
OUT_ROOT="/home/SB5/ocean_downscaling_products_pelagic"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

echo "Submitting curated ocean product pelagic-layer aggregation job:"
jid=$(
  sbatch --parsable --export=ALL,BIN_SET=pelagic,OUT_ROOT="${OUT_ROOT}" "${TOOL_SCRIPT}"
)

echo "  submitted as jobid=${jid}"
echo "Done."
