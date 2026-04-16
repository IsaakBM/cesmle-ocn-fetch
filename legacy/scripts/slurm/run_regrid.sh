#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLURM_SCRIPT="${SCRIPT_DIR}/regrid_cesm_pop_1deg.slurm.sh"

submit_and_wait () {
  local scen="$1"
  local var="$2"

  echo "Submitting: SCEN=${scen} VAR=${var}"
  jobid=$(SCEN="${scen}" VAR="${var}" sbatch \
    --parsable \
    --job-name="regrid_${scen}_${var}" \
    "$SLURM_SCRIPT")

  echo "Submitted jobid=${jobid}. Waiting..."
  # wait until job leaves the queue
  while squeue -j "$jobid" -h >/dev/null 2>&1; do
    sleep 60
  done
  echo "Done: jobid=${jobid} (SCEN=${scen} VAR=${var})"
}

# Example: run sequentially
submit_and_wait hist O2
#submit_and_wait hist TEMP
#submit_and_wait hist SALT
#submit_and_wait hist UVEL

#submit_and_wait rcp85 O2
#submit_and_wait rcp85 TEMP
#submit_and_wait rcp85 SALT
#submit_and_wait rcp85 UVEL