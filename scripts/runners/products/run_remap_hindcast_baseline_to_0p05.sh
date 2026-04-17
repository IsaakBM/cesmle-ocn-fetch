#!/usr/bin/env bash
# ==============================================================================
#  Runner for deriving hindcast baseline climatologies at 0.05 degree
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/remap_hindcast_baseline_to_0p05.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"
IN_ROOT="${IN_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25}"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
MEMORY="${MEMORY:-256G}"
WALLTIME="${WALLTIME:-2-00:00:00}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

mapfile -t VARS < <(
  find "${IN_ROOT}" -mindepth 1 -maxdepth 1 -type d \
    | while read -r d; do
        if [[ -d "${d}/clim_windows" ]]; then
          basename "${d}"
        fi
      done \
    | sort
)
if (( ${#VARS[@]} == 0 )); then
  echo "ERROR: No variable directories found under: ${IN_ROOT}"
  exit 1
fi

echo "Submitting hindcast baseline 0.25 -> 0.05 remap jobs by variable:"
echo "IN ROOT: ${IN_ROOT}"
for var in "${VARS[@]}"; do
  jid=$(
    sbatch --parsable \
      --job-name="hind05_${var}" \
      --partition="${PARTITION}" \
      --nodes="${NODES}" \
      --ntasks="${NTASKS}" \
      --cpus-per-task="${CPUS_PER_TASK}" \
      --mem="${MEMORY}" \
      --time="${WALLTIME}" \
      --output="${LOG_DIR}/hindcast_0p05_${var}_%j.out" \
      --error="${LOG_DIR}/hindcast_0p05_${var}_%j.err" \
      --export=ALL,IN_ROOT="${IN_ROOT}",VARS="${var}" \
      --wrap="bash '${TOOL_SCRIPT}'"
  )
  echo "  submitted VAR=${var} as jobid=${jid}"
done

echo "Done."
