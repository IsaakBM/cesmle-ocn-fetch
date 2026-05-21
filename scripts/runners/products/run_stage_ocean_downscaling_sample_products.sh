#!/usr/bin/env bash
# ==============================================================================
#  Runner for Shiny-viewer sample product staging
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/stage_ocean_downscaling_sample_products.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-1}"
MEMORY="${MEMORY:-16G}"
WALLTIME="${WALLTIME:-04:00:00}"

LAYERS_SOURCE_ROOT="${LAYERS_SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_layers_geotiff}"
PELAGIC_SOURCE_ROOT="${PELAGIC_SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_pelagic_geotiff}"
STAGE_ROOT="${STAGE_ROOT:-/home/SB5/ocean_downscaling_sample_products_geotiff}"
RESOLUTION="${RESOLUTION:-0p05}"
MEMBER="${MEMBER:-001}"
PHYSICAL_VARS="${PHYSICAL_VARS:-thetao so uo}"
EXTENSIONS="${EXTENSIONS:-tif tiff}"
DRY_RUN="${DRY_RUN:-yes}"
OVERWRITE="${OVERWRITE:-yes}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

if [[ ! -d "${LAYERS_SOURCE_ROOT}" ]]; then
  echo "ERROR: LAYERS_SOURCE_ROOT does not exist: ${LAYERS_SOURCE_ROOT}"
  exit 1
fi

if [[ ! -d "${PELAGIC_SOURCE_ROOT}" ]]; then
  echo "ERROR: PELAGIC_SOURCE_ROOT does not exist: ${PELAGIC_SOURCE_ROOT}"
  exit 1
fi

echo "Submitting Shiny-viewer sample product staging job:"
echo "LAYERS SOURCE  : ${LAYERS_SOURCE_ROOT}"
echo "PELAGIC SOURCE : ${PELAGIC_SOURCE_ROOT}"
echo "STAGE ROOT     : ${STAGE_ROOT}"
echo "RESOLUTION     : ${RESOLUTION}"
echo "MEMBER         : ${MEMBER}"
echo "DRY RUN        : ${DRY_RUN}"

jid=$(
  sbatch --parsable \
    --job-name="stage_sample_products" \
    --partition="${PARTITION}" \
    --nodes="${NODES}" \
    --ntasks="${NTASKS}" \
    --cpus-per-task="${CPUS_PER_TASK}" \
    --mem="${MEMORY}" \
    --time="${WALLTIME}" \
    --output="${LOG_DIR}/stage_sample_products_%j.out" \
    --error="${LOG_DIR}/stage_sample_products_%j.err" \
    --export=ALL,LAYERS_SOURCE_ROOT="${LAYERS_SOURCE_ROOT}",PELAGIC_SOURCE_ROOT="${PELAGIC_SOURCE_ROOT}",STAGE_ROOT="${STAGE_ROOT}",RESOLUTION="${RESOLUTION}",MEMBER="${MEMBER}",PHYSICAL_VARS="${PHYSICAL_VARS}",EXTENSIONS="${EXTENSIONS}",DRY_RUN="${DRY_RUN}",OVERWRITE="${OVERWRITE}" \
    "${TOOL_SCRIPT}"
)

echo "Submitted sample product staging as jobid=${jid}"
