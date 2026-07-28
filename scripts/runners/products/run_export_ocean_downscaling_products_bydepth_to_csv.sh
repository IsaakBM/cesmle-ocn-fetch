#!/usr/bin/env bash
# ==============================================================================
#  Runner for curated ocean downscaling by-depth NetCDF to CSV export
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit the by-depth NetCDF-to-CSV exporter as a single Slurm job.
#
# Notes:
#   - This mirrors:
#       /home/SB5/ocean_downscaling_products_bydepth
#     into:
#       /home/SB5/ocean_downscaling_products_bydepth_txt
#   - The main tool script carries the HPC resource requests.
#   - This runner stays lightweight and only handles submission.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/export_ocean_downscaling_products_bydepth_to_csv.sh"
FUTURE_MODELS="${FUTURE_MODELS:-auto}"
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS:-}"
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

echo "Submitting by-depth NetCDF-to-CSV export job:"
echo "FUTURE MODELS  : ${FUTURE_MODELS}"
echo "EXCLUDE FUTURE : ${EXCLUDE_FUTURE_MODELS:-<none>}"
echo "EXCLUDE NODES  : ${EXCLUDE_NODES:-<none>}"
sbatch_args=()
if [[ -n "${EXCLUDE_NODES}" ]]; then
  sbatch_args+=(--exclude="${EXCLUDE_NODES}")
fi
jid=$(
  sbatch --parsable \
    "${sbatch_args[@]}" \
    --export=ALL,FUTURE_MODELS="${FUTURE_MODELS}",EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS}" \
    "${TOOL_SCRIPT}"
)

echo "  submitted as jobid=${jid}"
echo "Done."
