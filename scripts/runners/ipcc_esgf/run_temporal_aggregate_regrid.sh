#!/usr/bin/env bash
# ==============================================================================
#  IPCC ESGF runner for generic temporal aggregation + regridder
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit IPCC/ESGF monthly time-series regridding jobs for selected
# scenario(s) and variable(s) using the generic temporal aggregation + regrid
# worker.
#
# Notes:
#   - This runner is intended for already-monthly time-series files downloaded
#     from ESGF/IPCC sources.
#   - No temporal aggregation is performed here.
#   - The runner only harmonizes/regrids the monthly files to a common 1 x 1
#     degree lon/lat grid.
#   - Expected input layout:
#       /home/SB5/ipcc_esgf_downloads/<scenario>/<variable>/*.nc
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/temporal_aggregate_regrid.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
SCENARIOS=(
  historical
  ssp585
)

VARS=(
  chl
  o2
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="ipcc_esgf"
INROOT_BASE="/home/SB5/ipcc_esgf_downloads"
OUTROOT_BASE="/home/SB5/ipcc_esgf_monthly_1deg"
METHOD="remapbil"
FILE_GLOB="*.nc"
PARTS_SUBDIR="parts"
TMP_SUBDIR="tmp"
MIN_FREE_GB=40
INPUT_LAYOUT="timeseries"
INPUT_TIMESTEP="monthly"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs
mkdir -p "$OUTROOT_BASE"

GRIDFILE="${OUTROOT_BASE}/grid_1deg_global.txt"
if [[ ! -s "$GRIDFILE" ]]; then
  cat > "$GRIDFILE" << 'EOF'
gridtype = lonlat
xsize    = 360
ysize    = 181
xfirst   = -180.0
xinc     = 1.0
yfirst   = -90.0
yinc     = 1.0
EOF
fi

echo "Submitting IPCC/ESGF monthly regrid jobs with generic worker:"
for scen in "${SCENARIOS[@]}"; do
  OUTROOT="${OUTROOT_BASE}/${scen}"

  if [[ ! -d "${INROOT_BASE}/${scen}" ]]; then
    echo "WARN: Scenario directory not found, skipping: ${INROOT_BASE}/${scen}"
    continue
  fi

  echo "Scenario: $scen"
  for v in "${VARS[@]}"; do
    INROOT="${INROOT_BASE}/${scen}/${v}"

    if [[ ! -d "$INROOT" ]]; then
      echo "  WARN: Variable directory not found, skipping: $INROOT"
      continue
    fi

    jid=$(DATASET_LABEL="${DATASET_LABEL}_${scen}" \
      VAR="$v" \
      INROOT="$INROOT" \
      OUTROOT="$OUTROOT" \
      GRIDFILE="$GRIDFILE" \
      INPUT_LAYOUT="$INPUT_LAYOUT" \
      INPUT_TIMESTEP="$INPUT_TIMESTEP" \
      METHOD="$METHOD" \
      FILE_GLOB="*.nc" \
      PARTS_SUBDIR="$PARTS_SUBDIR" \
      TMP_SUBDIR="$TMP_SUBDIR" \
      MIN_FREE_GB="$MIN_FREE_GB" \
      sbatch --parsable \
      --job-name="ipcc_${scen}_${v}" \
      "$CORE_SCRIPT")
    echo "  submitted SCENARIO=${scen} VAR=${v} as jobid=${jid}"
  done
done

echo "Done."
