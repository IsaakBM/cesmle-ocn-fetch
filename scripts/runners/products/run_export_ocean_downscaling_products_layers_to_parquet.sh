#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling fine-layer NetCDF to Parquet export
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/export_ocean_downscaling_products_to_parquet.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"
SOURCE_ROOT="${SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_layers}"
TARGET_ROOT="${TARGET_ROOT:-/home/SB5/ocean_downscaling_products_layers_parquet}"
OVERWRITE="${OVERWRITE:-no}"
RESOLUTIONS="${RESOLUTIONS:-auto}"
FUTURE_MODELS="${FUTURE_MODELS:-auto}"
# Production selection: omit retired branches; retain discovery of new models.
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS-cesm_f09_g16 legacy_downscaled_rcp85}"
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"
INCLUDE_BASELINE="${INCLUDE_BASELINE:-yes}"
SPLIT_ENSEMBLE_STATS="${SPLIT_ENSEMBLE_STATS:-yes}"
SPLIT_FUTURE_SCENARIOS="${SPLIT_FUTURE_SCENARIOS:-no}"
read -r -a FUTURE_MODEL_LIST <<< "${FUTURE_MODELS}"
read -r -a EXCLUDE_FUTURE_MODEL_LIST <<< "${EXCLUDE_FUTURE_MODELS}"

# shellcheck source=../../lib/product_export_subtrees.sh
source "${SCRIPT_DIR}/../../lib/product_export_subtrees.sh"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

if [[ ! -d "${SOURCE_ROOT}" ]]; then
  echo "ERROR: SOURCE_ROOT does not exist: ${SOURCE_ROOT}"
  exit 1
fi

select_product_export_subtrees

echo "Submitting curated ocean product layer Parquet export jobs by subtree:"
echo "SOURCE ROOT: ${SOURCE_ROOT}"
echo "TARGET ROOT: ${TARGET_ROOT}"
echo "OVERWRITE  : ${OVERWRITE}"
echo "RESOLUTIONS : ${RESOLUTIONS}"
echo "FUTURE MODELS : ${FUTURE_MODELS}"
echo "EXCLUDE FUTURE: ${EXCLUDE_FUTURE_MODELS:-<none>}"
echo "EXCLUDE NODES : ${EXCLUDE_NODES:-<none>}"
echo "INCLUDE BASELINE: ${INCLUDE_BASELINE}"
echo "SPLIT ENSEMBLE STATS: ${SPLIT_ENSEMBLE_STATS}"
echo "SPLIT FUTURE SCENARIOS: ${SPLIT_FUTURE_SCENARIOS}"
for subtree in "${SUBTREES[@]}"; do
  rel_path="${subtree#${SOURCE_ROOT}/}"
  out_subtree="${TARGET_ROOT}/${rel_path}"
  job_tag="$(echo "${rel_path}" | tr '/' '_' | tr -cd '[:alnum:]_')"
  sbatch_args=()
  if [[ -n "${EXCLUDE_NODES}" ]]; then
    sbatch_args+=(--exclude="${EXCLUDE_NODES}")
  fi
  jid=$(
    sbatch --parsable \
      --job-name="pqL_${job_tag}" \
      "${sbatch_args[@]}" \
      --output="${LOG_DIR}/parquet_layers_${job_tag}_%j.out" \
      --error="${LOG_DIR}/parquet_layers_${job_tag}_%j.err" \
      --export=ALL,IN_ROOT="${subtree}",OUT_ROOT="${out_subtree}",OVERWRITE="${OVERWRITE}",RESOLUTIONS="${RESOLUTIONS}",FUTURE_MODELS="${FUTURE_MODELS}",EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS}" \
      "${TOOL_SCRIPT}"
  )
  echo "  submitted SUBTREE=${rel_path} as jobid=${jid}"
done

echo "Done."
