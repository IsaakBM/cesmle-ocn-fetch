#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# NEW: point to the new Slurm script
SLURM_SCRIPT="${SCRIPT_DIR}/regrid_cesm_pop_1deg_homeout.slurm.sh"

submit_dep () {
  local scen="$1"
  local var="$2"
  local dep="${3:-}"

  if [[ -n "$dep" ]]; then
    SCEN="$scen" VAR="$var" sbatch --parsable \
      --dependency=afterok:"$dep" \
      --job-name="regrid_${scen}_${var}" \
      "$SLURM_SCRIPT"
  else
    SCEN="$scen" VAR="$var" sbatch --parsable \
      --job-name="regrid_${scen}_${var}" \
      "$SLURM_SCRIPT"
  fi
}

# ------------------------------------------------------------------------------
# One-at-a-time chain
# Start small, then uncomment progressively
# ------------------------------------------------------------------------------

jid=""

# --- HISTORICAL ---
#jid=$(submit_dep hist O2   "$jid")
#jid=$(submit_dep hist SALT "$jid")
#jid=$(submit_dep hist UVEL "$jid")
jid=$(submit_dep hist TEMP "$jid")

# --- RCP85 ---
#jid=$(submit_dep rcp85 O2   "$jid")
#jid=$(submit_dep rcp85 SALT "$jid")
#jid=$(submit_dep rcp85 UVEL "$jid")
#jid=$(submit_dep rcp85 TEMP "$jid")

echo "Submitted jobs. Last jobid: $jid"