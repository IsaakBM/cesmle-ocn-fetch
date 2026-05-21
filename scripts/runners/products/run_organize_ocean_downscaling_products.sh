#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling product tree organization
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit the copy-only curated product builder as multiple subtree jobs.
#
# Notes:
#   - This does NOT move or delete source data.
#   - It builds / refreshes:
#       /home/SB5/ocean_downscaling_products/
#   - It fans out by curated subtree and lets each worker copy files with
#     modest internal parallelism.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/organize_ocean_downscaling_products.sh"
LOG_DIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
MEMORY="${MEMORY:-64G}"
WALLTIME="${WALLTIME:-2-00:00:00}"
NPROC="${NPROC:-${CPUS_PER_TASK}}"
MODEL="${MODEL:-auto}"
SCENARIO="${SCENARIO:-auto}"
IPCC_DOWNSCALED_ROOT="${IPCC_DOWNSCALED_ROOT:-/home/SB5/downscaled}"
CESM_DOWNSCALED_ROOT="${CESM_DOWNSCALED_ROOT:-/home/SB5/downscaled_rcp85}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

declare -a TASKS=(
  "baseline chl"
  "baseline o2"
  "baseline thetao"
  "baseline so"
  "baseline uo"
  "future chl 2050-2060"
  "future chl 2090-2100"
  "future o2 2050-2060"
  "future o2 2090-2100"
  "future thetao 2050-2060"
  "future thetao 2090-2100"
  "future so 2050-2060"
  "future so 2090-2100"
  "future uo 2050-2060"
  "future uo 2090-2100"
)

echo "Submitting curated ocean product organization jobs by subtree:"
for task in "${TASKS[@]}"; do
  read -r scope var window <<<"${task}"
  job_tag="${scope}_${var}"
  wrap_cmd="ORGANIZE_SCOPE='${scope}' VAR='${var}' NPROC='${NPROC}' MODEL='${MODEL}' SCENARIO='${SCENARIO}' IPCC_DOWNSCALED_ROOT='${IPCC_DOWNSCALED_ROOT}' CESM_DOWNSCALED_ROOT='${CESM_DOWNSCALED_ROOT}'"
  if [[ "${scope}" == "future" ]]; then
    job_tag="${job_tag}_${window}"
    wrap_cmd="${wrap_cmd} WINDOW='${window}'"
  fi
  wrap_cmd="${wrap_cmd} bash '${TOOL_SCRIPT}'"

  jid=$(
    sbatch --parsable \
      --job-name="organize_${job_tag}" \
      --partition="${PARTITION}" \
      --nodes="${NODES}" \
      --ntasks="${NTASKS}" \
      --cpus-per-task="${CPUS_PER_TASK}" \
      --mem="${MEMORY}" \
      --time="${WALLTIME}" \
      --output="${LOG_DIR}/organize_${job_tag}_%j.out" \
      --error="${LOG_DIR}/organize_${job_tag}_%j.err" \
      --wrap="${wrap_cmd}"
  )
  echo "  submitted SCOPE=${scope} VAR=${var}${window:+ WINDOW=${window}} as jobid=${jid}"
done

echo "Done."
