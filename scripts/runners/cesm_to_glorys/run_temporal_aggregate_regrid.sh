#!/usr/bin/env bash
# ==============================================================================
#  CESM runner for generic temporal aggregation + regridder
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit CESM monthly time-series regridding jobs using the generic
# temporal aggregation + regrid worker.
#
# Notes:
#   - CESM POP files are already monthly time-series files.
#   - This runner regrids them to a regular 1 degree POP-style global grid
#     (360 x 180).
#   - Downstream CESM climatology/delta logic is currently centered on the
#     rcp85 branch, but this runner can also submit historical regrids.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/temporal_aggregate_regrid.slurm.sh"

SCENARIOS=(
  rcp85
)

VARS=(
  TEMP
  SALT
  O2
  UVEL
)

DATASET_LABEL="cesm"
INROOT_BASE="/home/sandbox-sparc/cesmle-ocn-fetch/cesm"
OUTROOT_BASE="/home/SB5"
METHOD="remapbil"
FILE_GLOB="*.nc*"
PARTS_SUBDIR="parts"
TMP_SUBDIR="tmp"
MIN_FREE_GB=60
INPUT_LAYOUT="timeseries"
INPUT_TIMESTEP="monthly"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

GRIDFILE="${OUTROOT_BASE}/grid_1deg_pop_global.txt"
if [[ ! -s "$GRIDFILE" ]]; then
  cat > "$GRIDFILE" << 'EOF'
gridtype = lonlat
xsize    = 360
ysize    = 180
xfirst   = -179.5
xinc     = 1.0
yfirst   = -89.5
yinc     = 1.0
EOF
fi

echo "Submitting CESM monthly regrid jobs with generic worker:"
for scen in "${SCENARIOS[@]}"; do
  OUTROOT="${OUTROOT_BASE}/${scen}"
  INROOT_SCEN="${INROOT_BASE}/${scen}"

  if [[ ! -d "${INROOT_SCEN}" ]]; then
    echo "WARN: Scenario directory not found, skipping: ${INROOT_SCEN}"
    continue
  fi

  echo "Scenario: ${scen}"
  for v in "${VARS[@]}"; do
    INROOT="${INROOT_SCEN}/${v}"

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
      FILE_GLOB="$FILE_GLOB" \
      PARTS_SUBDIR="$PARTS_SUBDIR" \
      TMP_SUBDIR="$TMP_SUBDIR" \
      MIN_FREE_GB="$MIN_FREE_GB" \
      sbatch --parsable \
      --job-name="cesm_${scen}_${v}" \
      "$CORE_SCRIPT")
    echo "  submitted SCENARIO=${scen} VAR=${v} as jobid=${jid}"
  done
done

echo "Done."
