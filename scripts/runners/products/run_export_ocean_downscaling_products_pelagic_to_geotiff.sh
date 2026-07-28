#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling pelagic NetCDF to GeoTIFF export
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/export_ocean_downscaling_products_to_geotiff.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"
SOURCE_ROOT="${SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_pelagic}"
TARGET_ROOT="${TARGET_ROOT:-/home/SB5/ocean_downscaling_products_pelagic_geotiff}"
OVERWRITE="${OVERWRITE:-no}"
FUTURE_MODELS="${FUTURE_MODELS:-auto}"
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS:-}"
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"
read -r -a FUTURE_MODEL_LIST <<< "${FUTURE_MODELS}"
read -r -a EXCLUDE_FUTURE_MODEL_LIST <<< "${EXCLUDE_FUTURE_MODELS}"

contains_word() {
  local needle="$1"
  shift
  local candidate

  for candidate in "$@"; do
    [[ "${candidate}" == "${needle}" ]] && return 0
  done
  return 1
}

include_subtree() {
  local subtree="$1"
  local rel_path model

  rel_path="${subtree#${SOURCE_ROOT}/}"
  case "${rel_path}" in
    baseline/*)
      return 0
      ;;
    future/*)
      model="${rel_path#future/}"
      model="${model%%/*}"
      if [[ -n "${EXCLUDE_FUTURE_MODELS}" ]] && contains_word "${model}" "${EXCLUDE_FUTURE_MODEL_LIST[@]}"; then
        return 1
      fi
      if [[ "${FUTURE_MODELS}" != "auto" ]] && ! contains_word "${model}" "${FUTURE_MODEL_LIST[@]}"; then
        return 1
      fi
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

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
  while IFS= read -r subtree; do
    include_subtree "${subtree}" && printf '%s\n' "${subtree}"
  done < <(
    find "${SOURCE_ROOT}/baseline" "${SOURCE_ROOT}/future" \
      -mindepth 1 \
      -maxdepth 1 \
      -type d \
      ! -name 'tmp*' \
      2>/dev/null | sort
  )
)
if (( ${#SUBTREES[@]} == 0 )); then
  echo "ERROR: No baseline/future variable directories found under: ${SOURCE_ROOT}"
  exit 1
fi

echo "Submitting curated ocean product pelagic GeoTIFF export jobs by subtree:"
echo "SOURCE ROOT: ${SOURCE_ROOT}"
echo "TARGET ROOT: ${TARGET_ROOT}"
echo "OVERWRITE  : ${OVERWRITE}"
echo "FUTURE MODELS : ${FUTURE_MODELS}"
echo "EXCLUDE FUTURE: ${EXCLUDE_FUTURE_MODELS:-<none>}"
echo "EXCLUDE NODES : ${EXCLUDE_NODES:-<none>}"
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
      --job-name="tifP_${job_tag}" \
      "${sbatch_args[@]}" \
      --output="${LOG_DIR}/geotiff_pelagic_${job_tag}_%j.out" \
      --error="${LOG_DIR}/geotiff_pelagic_${job_tag}_%j.err" \
      --cpus-per-task=5 \
      --export=ALL,IN_ROOT="${subtree}",OUT_ROOT="${out_subtree}",OVERWRITE="${OVERWRITE}",NPROC=5,FUTURE_MODELS="${FUTURE_MODELS}",EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS}" \
      "${TOOL_SCRIPT}"
  )
  echo "  submitted SUBTREE=${rel_path} as jobid=${jid}"
done

echo "Done."
