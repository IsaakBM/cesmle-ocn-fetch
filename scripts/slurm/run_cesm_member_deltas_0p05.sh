#!/usr/bin/env bash
# ==============================================================================
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit CESM member-delta jobs for selected variable(s)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLURM_SCRIPT="${SCRIPT_DIR}/cesm_member_deltas_0p05.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS=(
  O2
  #SALT
  #TEMP
  #UVEL
)

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

if [[ ${#VARS[@]} -eq 0 ]]; then
  echo "No variables selected."
  echo "Uncomment one here first, for example:"
  echo "VARS=("
  echo "  TEMP"
  echo "  #SALT"
  echo "  #O2"
  echo "  #UVEL"
  echo ")"
  exit 0
fi

echo "Submitting CESM member-delta jobs:"
for v in "${VARS[@]}"; do
  jid=$(VAR="${v}" sbatch --parsable \
    --job-name="delta_${v}" \
    "${SLURM_SCRIPT}")
  echo "  submitted VAR=${v} as jobid=${jid}"
done

echo "Done."