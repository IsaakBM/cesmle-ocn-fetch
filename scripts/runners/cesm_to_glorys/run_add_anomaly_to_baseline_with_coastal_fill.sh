#!/usr/bin/env bash
# ==============================================================================
#  CESM to GLORYS runner for baseline + anomaly adder with coastal fill
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit CESM-to-GLORYS downscaling jobs that add CESM deltas to the
# GLORYS baseline climatology while filling anomaly gaps on the trusted GLORYS
# wet mask.
#
# Notes:
#   - Keeps the historical CESM-to-GLORYS mapping:
#       * TEMP -> thetao
#       * SALT -> so
#       * UVEL -> uo
#   - Uses member-level deltas already regridded to 0.05 degree.
#   - Restores the legacy launch pattern:
#       one Slurm job per variable, member looping inside the worker
#   - Native output is already on the trusted 0.05 GLORYS grid, so no anomaly
#     remap is needed and no extra final regrid is requested.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/add_cesm_members_to_glorys_with_coastal_fill.slurm.sh"

VARS=(
  TEMP
  SALT
  UVEL
)

WINDOWS=(
  2050-2060
  2090-2100
)

DATASET_LABEL="cesm_to_glorys"
RCP85_ROOT="/home/SB5/rcp85"
GLORYS_ROOT="/home/SB5/glorys12v1_monthly_0p05"
OUTROOT="/home/SB5/downscaled_rcp85"
BASELINE_TAG="2006-2014"
OUT_SUFFIX="downscaled"

REMAP_ANOMALY_TO_BASELINE="no"
COASTAL_FILL="yes"
COASTAL_FILL_MAX_STEPS="12"
REGRID_OUTPUT="no"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

echo "Submitting CESM to GLORYS downscaling jobs with coastal fill:"
for v in "${VARS[@]}"; do
  jid=$(DATASET_LABEL="${DATASET_LABEL}" \
    VAR="${v}" \
    RCP85_ROOT="${RCP85_ROOT}" \
    GLORYS_ROOT="${GLORYS_ROOT}" \
    OUTROOT="${OUTROOT}" \
    BASELINE_TAG="${BASELINE_TAG}" \
    OUT_SUFFIX="${OUT_SUFFIX}" \
    REMAP_ANOMALY_TO_BASELINE="${REMAP_ANOMALY_TO_BASELINE}" \
    COASTAL_FILL="${COASTAL_FILL}" \
    COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS}" \
    WRITE_FILLED_ANOM="no" \
    sbatch --parsable \
    --job-name="addcf_${v}" \
    "${CORE_SCRIPT}")
  echo "  submitted VAR=${v} as jobid=${jid}"
done

echo "Done."
