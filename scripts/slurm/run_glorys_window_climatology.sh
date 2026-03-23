#!/usr/bin/env bash
# ==============================================================================
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit GLORYS baseline climatology jobs for selected variable(s)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLURM_SCRIPT="${SCRIPT_DIR}/glorys_window_climatology.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS=(
  bottomT
  mlotst
  so
  #thetao
  uo
  vo
  zos
)

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

if [[ ${#VARS[@]} -eq 0 ]]; then
  echo "No variables selected."
  echo "Uncomment one here first, for example:"
  echo "VARS=("
  echo "  thetao"
  echo "  #so"
  echo "  #uo"
  echo "  #vo"
  echo "  #mlotst"
  echo "  #zos"
  echo "  #bottomT"
  echo ")"
  exit 0
fi

echo "Submitting GLORYS climatology jobs:"
for v in "${VARS[@]}"; do
  jid=$(VAR="${v}" sbatch --parsable \
    --job-name="gclim_${v}" \
    "${SLURM_SCRIPT}")
  echo "  submitted VAR=${v} as jobid=${jid}"
done

echo "Done."