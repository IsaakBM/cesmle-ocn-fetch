#!/usr/bin/env bash
# ==============================================================================
#  Runner for filling hindcast baseline coastal gaps with a GLORYS wet mask
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================
#
# LEGACY CANDIDATE:
#   This submits the patch-style baseline coastal-fill tool. It is likely to move
#   to legacy after the planned all-variable 0.25 -> 0.05_glorys_coast
#   remap-and-fill runner replaces this intermediate step.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# This builds a separate coastal-filled baseline root, leaving the original
# hindcast baseline untouched.
#
# Default output:
#   /home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_coastal_filled
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/fill_hindcast_baseline_coastal_gaps.sh"
LOG_DIR="${LOG_DIR:-/home/sandbox-sparc/cesmle-ocn-fetch/logs}"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-1}"
MEMORY="${MEMORY:-256G}"
WALLTIME="${WALLTIME:-2-00:00:00}"

IN_ROOT="${IN_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_coastal_filled}"
VARS="${VARS:-chl o2 zos}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/glorys12v1_monthly_0p05}"
COASTAL_MASK_FILE="${COASTAL_MASK_FILE:-${GLORYS_ROOT}/thetao/clim_windows/glorys12v1_thetao_clim_2006-2014.nc}"
COASTAL_MASK_VAR="${COASTAL_MASK_VAR:-thetao}"
COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD:-distance_weighted}"
COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS:-12}"
COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER:-2.0}"
COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS:-4}"
OVERWRITE="${OVERWRITE:-no}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

read -r -a VAR_LIST <<< "${VARS}"

echo "Submitting hindcast baseline coastal-fill jobs:"
echo "IN ROOT          : ${IN_ROOT}"
echo "OUT ROOT         : ${OUT_ROOT}"
echo "VARS             : ${VAR_LIST[*]}"
echo "COASTAL MASK     : ${COASTAL_MASK_FILE}"
echo "COASTAL MASK VAR : ${COASTAL_MASK_VAR}"
echo "FILL METHOD      : ${COASTAL_FILL_METHOD}"
echo "FILL STEPS       : ${COASTAL_FILL_MAX_STEPS}"
echo "FILL POWER       : ${COASTAL_FILL_WEIGHT_POWER}"
echo "FILL DONORS      : ${COASTAL_FILL_MIN_DONORS}"
echo "OVERWRITE        : ${OVERWRITE}"

for var in "${VAR_LIST[@]}"; do
  wrap_cmd="IN_ROOT='${IN_ROOT}' OUT_ROOT='${OUT_ROOT}' VARS='${var}' COASTAL_MASK_FILE='${COASTAL_MASK_FILE}' COASTAL_MASK_VAR='${COASTAL_MASK_VAR}' COASTAL_FILL_METHOD='${COASTAL_FILL_METHOD}' COASTAL_FILL_MAX_STEPS='${COASTAL_FILL_MAX_STEPS}' COASTAL_FILL_WEIGHT_POWER='${COASTAL_FILL_WEIGHT_POWER}' COASTAL_FILL_MIN_DONORS='${COASTAL_FILL_MIN_DONORS}' OVERWRITE='${OVERWRITE}' bash '${TOOL_SCRIPT}'"

  jid=$(
    sbatch --parsable \
      --job-name="fillbase_${var}" \
      --partition="${PARTITION}" \
      --nodes="${NODES}" \
      --ntasks="${NTASKS}" \
      --cpus-per-task="${CPUS_PER_TASK}" \
      --mem="${MEMORY}" \
      --time="${WALLTIME}" \
      --output="${LOG_DIR}/fillbase_${var}_%j.out" \
      --error="${LOG_DIR}/fillbase_${var}_%j.err" \
      --wrap="${wrap_cmd}"
  )
  echo "  submitted VAR=${var} as jobid=${jid}"
done

echo "Done."
