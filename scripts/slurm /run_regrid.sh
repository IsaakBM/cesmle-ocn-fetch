#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for SCEN in hist rcp85; do
  for VAR in TEMP SALT O2 UVEL; do
    echo "Submitting job: SCEN=${SCEN} VAR=${VAR}"
    SCEN="${SCEN}" VAR="${VAR}" sbatch \
      --job-name="regrid_${SCEN}_${VAR}" \
      "${SCRIPT_DIR}/regrid_cesm_pop_1deg.slurm.sh"
  done
done
