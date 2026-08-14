#!/usr/bin/env bash
# ==============================================================================
#  Runner for Shiny-viewer sample product Cloud Optimized GeoTIFF creation
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/create_cog_sample_products.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

SOURCE_ROOT="${SOURCE_ROOT:-/home/SB5/ocean_downscaling_sample_products_geotiff}"
COG_ROOT="${COG_ROOT:-/home/SB5/ocean_downscaling_sample_products_cog}"
PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-5}"
MEMORY="${MEMORY:-32G}"
WALLTIME="${WALLTIME:-12:00:00}"
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"
OVERWRITE="${OVERWRITE:-no}"
DRY_RUN="${DRY_RUN:-yes}"
COMPRESS="${COMPRESS:-auto}"
BLOCKSIZE="${BLOCKSIZE:-256}"
OVERVIEW_RESAMPLING="${OVERVIEW_RESAMPLING:-NEAREST}"
VALIDATE="${VALIDATE:-yes}"
VALIDATE_RIO="${VALIDATE_RIO:-auto}"
SUBMIT_MODE="${SUBMIT_MODE:-subtrees}"
SPLIT_FUTURE_SCENARIOS="${SPLIT_FUTURE_SCENARIOS:-yes}"
SPLIT_ENSEMBLE_STATS="${SPLIT_ENSEMBLE_STATS:-yes}"
WRITE_MANIFESTS="${WRITE_MANIFESTS:-yes}"
EXPECT_LAYERS_ROWS="${EXPECT_LAYERS_ROWS:-7360}"
EXPECT_DEPTHS_ROWS="${EXPECT_DEPTHS_ROWS:-16648}"
EXPECT_COMBINED_ROWS="${EXPECT_COMBINED_ROWS:-24008}"
CHL_MAX_DEPTH_M="${CHL_MAX_DEPTH_M:-541.089}"

case "${DRY_RUN}" in yes|no) ;; *) echo "ERROR: DRY_RUN must be yes or no"; exit 1 ;; esac
case "${OVERWRITE}" in yes|no) ;; *) echo "ERROR: OVERWRITE must be yes or no"; exit 1 ;; esac
case "${VALIDATE}" in yes|no) ;; *) echo "ERROR: VALIDATE must be yes or no"; exit 1 ;; esac
case "${WRITE_MANIFESTS}" in yes|no) ;; *) echo "ERROR: WRITE_MANIFESTS must be yes or no"; exit 1 ;; esac
case "${SUBMIT_MODE}" in subtrees|single|validate_only) ;; *) echo "ERROR: SUBMIT_MODE must be subtrees, single, or validate_only"; exit 1 ;; esac

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi
if [[ ! -d "${SOURCE_ROOT}" ]]; then
  echo "ERROR: SOURCE_ROOT does not exist: ${SOURCE_ROOT}"
  exit 1
fi

submit_job() {
  local job_name="$1"
  local rel_prefix="$2"
  local write_manifests="$3"
  local validate="$4"
  local convert_files="$5"
  local dependency="${6:-}"
  local job_tag
  local -a sbatch_args

  job_tag="$(echo "${job_name}" | tr '/' '_' | tr -cd '[:alnum:]_')"
  sbatch_args=()
  if [[ -n "${EXCLUDE_NODES}" ]]; then
    sbatch_args+=(--exclude="${EXCLUDE_NODES}")
  fi
  if [[ -n "${dependency}" ]]; then
    sbatch_args+=(--dependency="afterok:${dependency}")
  fi

  sbatch --parsable \
    --job-name="${job_tag}" \
    "${sbatch_args[@]}" \
    --partition="${PARTITION}" \
    --nodes="${NODES}" \
    --ntasks="${NTASKS}" \
    --cpus-per-task="${CPUS_PER_TASK}" \
    --mem="${MEMORY}" \
    --time="${WALLTIME}" \
    --output="${LOG_DIR}/${job_tag}_%j.out" \
    --error="${LOG_DIR}/${job_tag}_%j.err" \
    --export=ALL,SOURCE_ROOT="${SOURCE_ROOT}",COG_ROOT="${COG_ROOT}",RELATIVE_PREFIX="${rel_prefix}",OVERWRITE="${OVERWRITE}",DRY_RUN="${DRY_RUN}",CONVERT_FILES="${convert_files}",COMPRESS="${COMPRESS}",BLOCKSIZE="${BLOCKSIZE}",OVERVIEW_RESAMPLING="${OVERVIEW_RESAMPLING}",NPROC="${CPUS_PER_TASK}",WRITE_MANIFESTS="${write_manifests}",VALIDATE="${validate}",VALIDATE_RIO="${VALIDATE_RIO}",EXPECT_LAYERS_ROWS="${EXPECT_LAYERS_ROWS}",EXPECT_DEPTHS_ROWS="${EXPECT_DEPTHS_ROWS}",EXPECT_COMBINED_ROWS="${EXPECT_COMBINED_ROWS}",CHL_MAX_DEPTH_M="${CHL_MAX_DEPTH_M}" \
    "${TOOL_SCRIPT}"
}

collect_subtrees() {
  local root rel_path scenario_depth
  local -a first_pass expanded scenario_subtrees

  first_pass=()
  while IFS= read -r root; do
    first_pass+=("${root}")
  done < <(
    find "${SOURCE_ROOT}/layers" "${SOURCE_ROOT}/depths" \
      -mindepth 1 \
      -maxdepth 2 \
      -type d \
      2>/dev/null | sort
  )

  expanded=()
  for root in "${first_pass[@]}"; do
    rel_path="${root#${SOURCE_ROOT}/}"
    case "${rel_path}" in
      layers/baseline/*|depths/baseline/*)
        expanded+=("${root}")
        ;;
      layers/future/*|depths/future/*)
        expanded+=("${root}")
        ;;
    esac
  done

  if [[ "${SPLIT_ENSEMBLE_STATS}" == "yes" ]]; then
    first_pass=("${expanded[@]}")
    expanded=()
    for root in "${first_pass[@]}"; do
      rel_path="${root#${SOURCE_ROOT}/}"
      if [[ "${rel_path}" == layers/future/ensemble || "${rel_path}" == depths/future/ensemble ]]; then
        scenario_subtrees=()
        while IFS= read -r subtree; do
          scenario_subtrees+=("${subtree}")
        done < <(find "${root}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
        if (( ${#scenario_subtrees[@]} > 0 )); then
          expanded+=("${scenario_subtrees[@]}")
        else
          expanded+=("${root}")
        fi
      else
        expanded+=("${root}")
      fi
    done
  fi

  if [[ "${SPLIT_FUTURE_SCENARIOS}" == "yes" ]]; then
    first_pass=("${expanded[@]}")
    expanded=()
    for root in "${first_pass[@]}"; do
      rel_path="${root#${SOURCE_ROOT}/}"
      if [[ "${rel_path}" == layers/future/* || "${rel_path}" == depths/future/* ]]; then
        scenario_depth=2
        if [[ "${rel_path}" == layers/future/ensemble/* || "${rel_path}" == depths/future/ensemble/* ]]; then
          scenario_depth=1
        fi
        scenario_subtrees=()
        while IFS= read -r subtree; do
          scenario_subtrees+=("${subtree}")
        done < <(find "${root}" -mindepth "${scenario_depth}" -maxdepth "${scenario_depth}" -type d 2>/dev/null | sort)
        if (( ${#scenario_subtrees[@]} > 0 )); then
          expanded+=("${scenario_subtrees[@]}")
        else
          expanded+=("${root}")
        fi
      else
        expanded+=("${root}")
      fi
    done
  fi

  printf '%s\n' "${expanded[@]}" | sort -u
}

echo "Submitting Shiny-viewer COG sample product workflow:"
echo "SOURCE ROOT       : ${SOURCE_ROOT}"
echo "COG ROOT          : ${COG_ROOT}"
echo "SUBMIT MODE       : ${SUBMIT_MODE}"
echo "DRY RUN           : ${DRY_RUN}"
echo "OVERWRITE         : ${OVERWRITE}"
echo "COMPRESS          : ${COMPRESS}"
echo "CPUS PER TASK     : ${CPUS_PER_TASK}"
echo "VALIDATE          : ${VALIDATE}"
echo "RIO VALIDATE      : ${VALIDATE_RIO}"
echo "EXPECTED ROWS     : layers=${EXPECT_LAYERS_ROWS} depths=${EXPECT_DEPTHS_ROWS} combined=${EXPECT_COMBINED_ROWS}"
echo "EXCLUDE NODES     : ${EXCLUDE_NODES:-<none>}"

if [[ "${SUBMIT_MODE}" == "single" ]]; then
  jid="$(submit_job "cog_sample_all" "" "${WRITE_MANIFESTS}" "${VALIDATE}" "yes")"
  echo "Submitted all-tree COG sample product job as jobid=${jid}"
  exit 0
fi

if [[ "${SUBMIT_MODE}" == "validate_only" ]]; then
  jid="$(submit_job "cog_sample_validate" "" "${WRITE_MANIFESTS}" "${VALIDATE}" "no")"
  echo "Submitted COG manifest/full-tree validation job as jobid=${jid}"
  exit 0
fi

SUBTREES=()
while IFS= read -r subtree; do
  SUBTREES+=("${subtree}")
done < <(collect_subtrees)
if (( ${#SUBTREES[@]} == 0 )); then
  echo "ERROR: No layers/depths subtrees found under: ${SOURCE_ROOT}"
  exit 1
fi

job_ids=()
for subtree in "${SUBTREES[@]}"; do
  rel_path="${subtree#${SOURCE_ROOT}/}"
  job_tag="cog_${rel_path}"
  jid="$(submit_job "${job_tag}" "${rel_path}" "no" "${VALIDATE}" "yes")"
  job_ids+=("${jid}")
  echo "  submitted RELATIVE_PREFIX=${rel_path} as jobid=${jid}"
done

dependency="$(IFS=:; echo "${job_ids[*]}")"
final_jid="$(submit_job "cog_sample_finalize" "" "${WRITE_MANIFESTS}" "${VALIDATE}" "no" "${dependency}")"
echo "Submitted manifest/full-tree validation job as jobid=${final_jid} afterok:${dependency}"
echo "Done."
