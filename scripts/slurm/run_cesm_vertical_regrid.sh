#!/usr/bin/env bash
# ==============================================================================
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit CESM vertical regridding jobs for selected variable(s)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLURM_SCRIPT="${SCRIPT_DIR}/cesm_vertical_regrid.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS=(
  #O2
  SALT
  TEMP
  UVEL
)

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

if [[ ${#VARS[@]} -eq 0 ]]; then
  echo "No variables selected."
  echo "Uncomment one here first, for example:"
  echo "VARS=("
  echo "  O2"
  echo "  #SALT"
  echo "  #TEMP"
  echo "  #UVEL"
  echo ")"
  exit 0
fi

echo "Submitting CESM vertical regridding jobs:"
for v in "${VARS[@]}"; do
  jid=$(VAR="${v}" sbatch --parsable \
    --job-name="vgrid_${v}" \
    "${SLURM_SCRIPT}")
  echo "  submitted VAR=${v} as jobid=${jid}"
done

echo "Done."