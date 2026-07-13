#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling individual-depth NetCDF to Parquet export
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/export_ocean_downscaling_products_to_parquet.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"
MAX_DEPTH_M="${MAX_DEPTH_M:-}"
MAX_DEPTH_M_LOWER="${MAX_DEPTH_M,,}"
if [[ -z "${SOURCE_ROOT:-}" ]]; then
  if [[ -n "${MAX_DEPTH_M}" && "${MAX_DEPTH_M_LOWER}" != "all" ]]; then
    SOURCE_ROOT="/home/SB5/ocean_downscaling_products_depths"
  else
    SOURCE_ROOT="/home/SB5/ocean_downscaling_products_bydepth"
  fi
fi
if [[ -z "${TARGET_ROOT:-}" ]]; then
  if [[ -n "${MAX_DEPTH_M}" && "${MAX_DEPTH_M_LOWER}" != "all" ]]; then
    TARGET_ROOT="/home/SB5/ocean_downscaling_products_depths_parquet"
  else
    TARGET_ROOT="/home/SB5/ocean_downscaling_products_bydepth_parquet"
  fi
fi
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

mapfile -t SUBTREES < <(
  find "${SOURCE_ROOT}/baseline" "${SOURCE_ROOT}/future" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    ! -name 'tmp*' \
    2>/dev/null | sort
)
if (( ${#SUBTREES[@]} == 0 )); then
  echo "ERROR: No baseline/future variable directories found under: ${SOURCE_ROOT}"
  exit 1
fi

echo "Submitting curated ocean product individual-depth Parquet export jobs by subtree:"
echo "SOURCE ROOT: ${SOURCE_ROOT}"
echo "TARGET ROOT: ${TARGET_ROOT}"
echo "MAX DEPTH M: ${MAX_DEPTH_M:-<all>}"
echo "OVERWRITE  : ${OVERWRITE}"
for subtree in "${SUBTREES[@]}"; do
  rel_path="${subtree#${SOURCE_ROOT}/}"
  out_subtree="${TARGET_ROOT}/${rel_path}"
  job_tag="$(echo "${rel_path}" | tr '/' '_' | tr -cd '[:alnum:]_')"
  jid=$(
    sbatch --parsable \
      --job-name="pqD_${job_tag}" \
      --output="${LOG_DIR}/parquet_depths_${job_tag}_%j.out" \
      --error="${LOG_DIR}/parquet_depths_${job_tag}_%j.err" \
      --export=ALL,IN_ROOT="${subtree}",OUT_ROOT="${out_subtree}",OVERWRITE="${OVERWRITE}" \
      "${TOOL_SCRIPT}"
  )
  echo "  submitted SUBTREE=${rel_path} as jobid=${jid}"
done

echo "Done."
