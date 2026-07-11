#!/usr/bin/env bash
# ==============================================================================
#  Runner for deriving 0.05 hindcast baselines with GLORYS coastline filling
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh"
LOG_DIR="${LOG_DIR:-/home/sandbox-sparc/cesmle-ocn-fetch/logs}"

IN_ROOT="${IN_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast}"
GRIDFILE="${GRIDFILE:-/home/SB5/glorys12v1_monthly_0p05/grid_0p05_global.txt}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/glorys12v1_monthly_0p05}"
COASTAL_MASK_FILE="${COASTAL_MASK_FILE:-${GLORYS_ROOT}/thetao/clim_windows/glorys12v1_thetao_clim_2006-2014.nc}"
COASTAL_MASK_VAR="${COASTAL_MASK_VAR:-thetao}"
COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD:-distance_weighted}"
COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS:-12}"
COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER:-2.0}"
COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS:-4}"
COASTAL_FILL_REQUIRE_COMPLETE="${COASTAL_FILL_REQUIRE_COMPLETE:-yes}"
METHOD="${METHOD:-auto}"
AUTO_METHOD_DEFAULT="${AUTO_METHOD_DEFAULT:-remapbil}"
AUTO_METHOD_CURVILINEAR="${AUTO_METHOD_CURVILINEAR:-remapdis}"
OVERWRITE="${OVERWRITE:-yes}"
VARS="${VARS:-}"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
MEMORY="${MEMORY:-256G}"
WALLTIME="${WALLTIME:-2-00:00:00}"
NPROC="${NPROC:-${CPUS_PER_TASK}}"
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ -z "${VARS}" ]]; then
  mapfile -t VAR_LIST < <(
    find "${IN_ROOT}" -mindepth 1 -maxdepth 1 -type d \
      | while read -r d; do
          if [[ -d "${d}/clim_windows" ]]; then
            basename "${d}"
          fi
        done \
      | sort
  )
else
  read -r -a VAR_LIST <<< "${VARS}"
fi

if (( ${#VAR_LIST[@]} == 0 )); then
  echo "ERROR: No variable directories found under: ${IN_ROOT}"
  exit 1
fi

echo "Submitting hindcast 0.25 -> 0.05 GLORYS-coast jobs by variable:"
echo "IN ROOT          : ${IN_ROOT}"
echo "OUT ROOT         : ${OUT_ROOT}"
echo "VARS             : ${VAR_LIST[*]}"
echo "GRIDFILE         : ${GRIDFILE}"
echo "COASTAL MASK     : ${COASTAL_MASK_FILE}"
echo "COASTAL MASK VAR : ${COASTAL_MASK_VAR}"
echo "FILL METHOD      : ${COASTAL_FILL_METHOD}"
echo "FILL STEPS       : ${COASTAL_FILL_MAX_STEPS}"
echo "FILL POWER       : ${COASTAL_FILL_WEIGHT_POWER}"
echo "FILL DONORS      : ${COASTAL_FILL_MIN_DONORS}"
echo "REQUIRE COMPLETE : ${COASTAL_FILL_REQUIRE_COMPLETE}"
echo "METHOD           : ${METHOD}"
echo "OVERWRITE        : ${OVERWRITE}"
echo "EXCLUDE NODES    : ${EXCLUDE_NODES:-<none>}"

for var in "${VAR_LIST[@]}"; do
  sbatch_args=()
  if [[ -n "${EXCLUDE_NODES}" ]]; then
    sbatch_args+=(--exclude="${EXCLUDE_NODES}")
  fi

  jid=$(
    sbatch --parsable \
      --job-name="hind05gc_${var}" \
      --partition="${PARTITION}" \
      --nodes="${NODES}" \
      --ntasks="${NTASKS}" \
      --cpus-per-task="${CPUS_PER_TASK}" \
      --mem="${MEMORY}" \
      --time="${WALLTIME}" \
      --output="${LOG_DIR}/hindcast_0p05_glorys_coast_${var}_%j.out" \
      --error="${LOG_DIR}/hindcast_0p05_glorys_coast_${var}_%j.err" \
      "${sbatch_args[@]}" \
      --export=ALL,IN_ROOT="${IN_ROOT}",OUT_ROOT="${OUT_ROOT}",GRIDFILE="${GRIDFILE}",VARS="${var}",METHOD="${METHOD}",AUTO_METHOD_DEFAULT="${AUTO_METHOD_DEFAULT}",AUTO_METHOD_CURVILINEAR="${AUTO_METHOD_CURVILINEAR}",COASTAL_MASK_FILE="${COASTAL_MASK_FILE}",COASTAL_MASK_VAR="${COASTAL_MASK_VAR}",COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD}",COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS}",COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER}",COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS}",COASTAL_FILL_REQUIRE_COMPLETE="${COASTAL_FILL_REQUIRE_COMPLETE}",OVERWRITE="${OVERWRITE}",NPROC="${NPROC}" \
      --wrap="bash '${TOOL_SCRIPT}'"
  )
  echo "  submitted VAR=${var} as jobid=${jid}"
done

echo "Done."
