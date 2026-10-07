#!/usr/bin/env bash
# ==============================================================================
#  Slurm runner for climatology source-coverage audit
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Submit the read-only source-coverage audit as one Slurm job
#    - Check CMIP6, GLORYS, and biogeochemistry-hindcast inputs required by the
#      planned monthly and season-ready climatology products
#    - Write a reviewable CSV report without modifying or downloading source data
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/audit_climatology_source_coverage.py"

# ==============================================================================
# Optional env vars
#   OUT_FILE       : CSV report written by the audit
#   LOG_DIR        : Slurm stdout/stderr directory
#   PARTITION      : Slurm partition (default: grit_nodes)
#   CPUS_PER_TASK  : requested CPUs (default: 1; audit is sequential)
#   MEMORY         : requested memory (default: 8G)
#   WALLTIME       : requested walltime (default: 04:00:00)
#
# The tool also accepts environment overrides for roots and selections:
#   IPCC_DOWNLOAD_ROOT, IPCC_LEGACY_DOWNLOAD_ROOT, IPCC_MONTHLY_ROOT,
#   GLORYS_ROOT, HINDCAST_ROOT, MANIFEST, MODELS, SCENARIOS, IPCC_VARS,
#   GLORYS_VARS, and HINDCAST_VARS.
# ==============================================================================
OUT_FILE="${OUT_FILE:-${REPO_ROOT}/data/manifests/climatology_source_coverage_audit.csv}"
LOG_DIR="${LOG_DIR:-${REPO_ROOT}/logs}"
PARTITION="${PARTITION:-grit_nodes}"
CPUS_PER_TASK="${CPUS_PER_TASK:-1}"
MEMORY="${MEMORY:-8G}"
WALLTIME="${WALLTIME:-04:00:00}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Audit tool is missing or not executable: ${TOOL_SCRIPT}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" "$(dirname "${OUT_FILE}")"

echo "Submitting climatology source-coverage audit:"
echo "  tool      : ${TOOL_SCRIPT}"
echo "  report    : ${OUT_FILE}"
echo "  log dir   : ${LOG_DIR}"
echo "  partition : ${PARTITION}"
echo "  walltime  : ${WALLTIME}"
echo "  mode      : read-only"

jid="$(sbatch --parsable \
  --partition="${PARTITION}" \
  --job-name="audit_clim_sources" \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task="${CPUS_PER_TASK}" \
  --mem="${MEMORY}" \
  --time="${WALLTIME}" \
  --chdir="${REPO_ROOT}" \
  --output="${LOG_DIR}/audit_clim_sources_%j.out" \
  --error="${LOG_DIR}/audit_clim_sources_%j.err" \
  --export=ALL,OUT_FILE="${OUT_FILE}" \
  "${TOOL_SCRIPT}")"

echo "Submitted climatology source-coverage audit as jobid=${jid}"
