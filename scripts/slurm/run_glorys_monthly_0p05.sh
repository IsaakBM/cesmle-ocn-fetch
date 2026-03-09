#!/usr/bin/env bash
# ==============================================================================
# Runner: submit GLORYS monthly baseline jobs by year for selected variable(s)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLURM_SCRIPT="${SCRIPT_DIR}/glorys_monthly_0p05.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS=(
  thetao
  #so
  #mlotst
  #uo
  #vo
  #zos
  #bottomT
)

YEARS=(
  2006
  2007
  2008
  #2009
  #2010
  #2011
  #2012
  #2013
  #2014
)

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting GLORYS monthly jobs by year:"
for v in "${VARS[@]}"; do
  echo "Variable: $v"
  for y in "${YEARS[@]}"; do
    jid=$(VAR="$v" YEAR="$y" sbatch --parsable \
      --job-name="glorys_${v}_${y}" \
      "$SLURM_SCRIPT")
    echo "  submitted VAR=${v} YEAR=${y} as jobid=${jid}"
  done
done

echo "Done."