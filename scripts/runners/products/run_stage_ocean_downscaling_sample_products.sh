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
DEPTHS_SOURCE_ROOT="${DEPTHS_SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_depths_geotiff}"
STAGE_ROOT="${STAGE_ROOT:-/home/SB5/ocean_downscaling_sample_products_geotiff}"
RESOLUTION="${RESOLUTION:-0p05}"
PRODUCT_FAMILIES="${PRODUCT_FAMILIES:-layers depths}"
MEMBER="${MEMBER:-001}"
PHYSICAL_VARS="${PHYSICAL_VARS:-thetao so uo}"
EXTENSIONS="${EXTENSIONS:-tif tiff}"
DRY_RUN="${DRY_RUN:-yes}"
OVERWRITE="${OVERWRITE:-yes}"
STAGE_MANIFESTS="${STAGE_MANIFESTS:-yes}"
CLEAN_STAGE_ROOT="${CLEAN_STAGE_ROOT:-no}"
STAGE_DEPTHS="${STAGE_DEPTHS:-yes}"
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS:-cesm_f09_g16 legacy_downscaled_rcp85}"
EXCLUDE_FUTURE_SCENARIOS="${EXCLUDE_FUTURE_SCENARIOS:-rcp85}"

contains_word() {
  local needle="$1"
  shift
  local candidate

  for candidate in "$@"; do
    [[ "${candidate}" == "${needle}" ]] && return 0
  done
  return 1
}

read -r -a PRODUCT_FAMILY_LIST <<< "${PRODUCT_FAMILIES}"
for product_family in "${PRODUCT_FAMILY_LIST[@]}"; do
  case "${product_family}" in
    layers|pelagic|depths) ;;
    *)
      echo "ERROR: Unsupported PRODUCT_FAMILIES entry: ${product_family}"
      echo "Supported product families: layers pelagic depths"
      exit 1
      ;;
  esac
done

include_product_family() {
  local product_family="$1"
  contains_word "${product_family}" "${PRODUCT_FAMILY_LIST[@]}"
}

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

if include_product_family "layers" && [[ ! -d "${LAYERS_SOURCE_ROOT}" ]]; then
  echo "ERROR: LAYERS_SOURCE_ROOT does not exist: ${LAYERS_SOURCE_ROOT}"
  exit 1
fi

if include_product_family "pelagic" && [[ ! -d "${PELAGIC_SOURCE_ROOT}" ]]; then
  echo "ERROR: PELAGIC_SOURCE_ROOT does not exist: ${PELAGIC_SOURCE_ROOT}"
  exit 1
fi

if include_product_family "depths" && [[ "${STAGE_DEPTHS}" == "yes" && ! -d "${DEPTHS_SOURCE_ROOT}" ]]; then
  echo "ERROR: DEPTHS_SOURCE_ROOT does not exist: ${DEPTHS_SOURCE_ROOT}"
  exit 1
fi

echo "Submitting Shiny-viewer sample product staging job:"
echo "LAYERS SOURCE  : ${LAYERS_SOURCE_ROOT}"
echo "PELAGIC SOURCE : ${PELAGIC_SOURCE_ROOT}"
echo "DEPTHS SOURCE  : ${DEPTHS_SOURCE_ROOT}"
echo "STAGE ROOT     : ${STAGE_ROOT}"
echo "RESOLUTION     : ${RESOLUTION}"
echo "PRODUCT FAMILY : ${PRODUCT_FAMILIES}"
echo "FUTURE LAYOUT  : future/<model>/<realization_or_statistic>/<scenario>/<variable>/<window>/<resolution>"
echo "REALIZATION    : first sorted per non-ensemble model/scenario/variable/window"
echo "EXCLUDE MODELS : ${EXCLUDE_FUTURE_MODELS}"
echo "EXCLUDE SCEN.  : ${EXCLUDE_FUTURE_SCENARIOS}"
echo "DRY RUN        : ${DRY_RUN}"
echo "STAGE MANIFESTS: ${STAGE_MANIFESTS}"
echo "CLEAN STAGE    : ${CLEAN_STAGE_ROOT}"
echo "STAGE DEPTHS   : ${STAGE_DEPTHS}"

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
    --export=ALL,LAYERS_SOURCE_ROOT="${LAYERS_SOURCE_ROOT}",PELAGIC_SOURCE_ROOT="${PELAGIC_SOURCE_ROOT}",DEPTHS_SOURCE_ROOT="${DEPTHS_SOURCE_ROOT}",STAGE_ROOT="${STAGE_ROOT}",RESOLUTION="${RESOLUTION}",PRODUCT_FAMILIES="${PRODUCT_FAMILIES}",MEMBER="${MEMBER}",PHYSICAL_VARS="${PHYSICAL_VARS}",EXTENSIONS="${EXTENSIONS}",DRY_RUN="${DRY_RUN}",OVERWRITE="${OVERWRITE}",STAGE_MANIFESTS="${STAGE_MANIFESTS}",CLEAN_STAGE_ROOT="${CLEAN_STAGE_ROOT}",STAGE_DEPTHS="${STAGE_DEPTHS}",EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS}",EXCLUDE_FUTURE_SCENARIOS="${EXCLUDE_FUTURE_SCENARIOS}" \
    "${TOOL_SCRIPT}"
)

echo "Submitted sample product staging as jobid=${jid}"
