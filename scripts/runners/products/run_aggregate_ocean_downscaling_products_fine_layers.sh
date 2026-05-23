#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling fine depth-layer aggregation
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/aggregate_ocean_downscaling_products_by_depth_bins.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"
SOURCE_ROOT="${SOURCE_ROOT:-/home/SB5/ocean_downscaling_products}"
TARGET_ROOT="${TARGET_ROOT:-/home/SB5/ocean_downscaling_products_layers}"
OVERWRITE="${OVERWRITE:-no}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

if [[ ! -d "${SOURCE_ROOT}" ]]; then
  echo "ERROR: SOURCE_ROOT does not exist: ${SOURCE_ROOT}"
  exit 1
fi

mapfile -t SUBTREES < <({
  find "${SOURCE_ROOT}/baseline" -mindepth 0 -maxdepth 0 -type d 2>/dev/null
  find "${SOURCE_ROOT}/future" -mindepth 3 -maxdepth 3 -type d 2>/dev/null
} | sort)
if (( ${#SUBTREES[@]} == 0 )); then
  echo "ERROR: No baseline/future aggregation subtrees found under: ${SOURCE_ROOT}"
  exit 1
fi

echo "Submitting curated ocean product fine depth-layer aggregation jobs by subtree:"
echo "SOURCE ROOT: ${SOURCE_ROOT}"
echo "TARGET ROOT: ${TARGET_ROOT}"
echo "OVERWRITE  : ${OVERWRITE}"
for subtree in "${SUBTREES[@]}"; do
  rel_path="${subtree#${SOURCE_ROOT}/}"
  out_subtree="${TARGET_ROOT}/${rel_path}"
  job_tag="$(echo "${rel_path}" | tr '/' '_' | tr -cd '[:alnum:]_')"
  jid=$(
    sbatch --parsable \
      --job-name="fine_${job_tag}" \
      --output="${LOG_DIR}/fine_layers_${job_tag}_%j.out" \
      --error="${LOG_DIR}/fine_layers_${job_tag}_%j.err" \
      --export=ALL,BIN_SET=fine,IN_ROOT="${subtree}",OUT_ROOT="${out_subtree}",OVERWRITE="${OVERWRITE}" \
      "${TOOL_SCRIPT}"
  )
  echo "  submitted SUBTREE=${rel_path} as jobid=${jid}"
done

echo "Done."
