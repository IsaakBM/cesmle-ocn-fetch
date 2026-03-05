#!/usr/bin/env bash
# ==============================================================================
# Runner: submit 7 GLORYS monthly baseline jobs (one job per variable)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLURM_SCRIPT="${SCRIPT_DIR}/glorys_monthly_0p05.slurm.sh"

VARS=(
  #thetao
  #so
  #mlotst
  uo
  #vo
  zos
  bottomT
)

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting GLORYS monthly jobs (one per variable):"
for v in "${VARS[@]}"; do
  jid=$(VAR="$v" sbatch --parsable \
    --job-name="glorys_${v}_monmean_0p05" \
    "$SLURM_SCRIPT")
  echo "  submitted VAR=${v} as jobid=${jid}"
done

echo "Done."