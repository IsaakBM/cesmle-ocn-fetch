#!/usr/bin/env bash
# ==============================================================================
#  GLORYS12v1 runner for generic temporal aggregation + regridder
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit monthly jobs by year for selected GLORYS variable(s) using the
# generic temporal aggregation + regrid worker.
#
# Notes:
#   - This runner is intended for daily GLORYS12v1 files organized as
#     YEAR/MONTH directories.
#   - It builds monthly means and harmonizes them to a 0.05 x 0.05 degree
#     global grid.
#   - Expected input layout:
#       /home/sandbox-sparc/cesmle-ocn-fetch/glorys12v1/<year>/<month>/*.nc*
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/temporal_aggregate_regrid.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS=(
  thetao
  so
  mlotst
  uo
  vo
  zos
  bottomT
)

YEARS=(
  2006
  2007
  2008
  2009
  2010
  2011
  2012
  2013
  2014
)

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="glorys12v1"
INROOT="/home/sandbox-sparc/cesmle-ocn-fetch/glorys12v1"
OUTROOT="/home/SB5/glorys12v1_monthly_0p05"
GRIDFILE="${OUTROOT}/grid_0p05_global.txt"
METHOD="remapbil"
FILE_GLOB="*.nc*"
PARTS_SUBDIR="parts"
TMP_SUBDIR="tmp"
MIN_FREE_GB=40
INPUT_TIMESTEP="daily"
INPUT_LAYOUT="year_month"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs
mkdir -p "$OUTROOT"

if [[ ! -s "$GRIDFILE" ]]; then
  cat > "$GRIDFILE" << 'EOF'
gridtype = lonlat
xsize    = 7200
ysize    = 3601
xfirst   = -180.0
xinc     = 0.05
yfirst   = -90.0
yinc     = 0.05
EOF
fi

echo "Submitting GLORYS monthly jobs by year with generic worker:"
echo "Dataset: $DATASET_LABEL"
for v in "${VARS[@]}"; do
  echo "Variable: $v"
  for y in "${YEARS[@]}"; do
    jid=$(DATASET_LABEL="$DATASET_LABEL" \
      VAR="$v" \
      YEAR="$y" \
      INROOT="$INROOT" \
      OUTROOT="$OUTROOT" \
      GRIDFILE="$GRIDFILE" \
      METHOD="$METHOD" \
      FILE_GLOB="$FILE_GLOB" \
      PARTS_SUBDIR="$PARTS_SUBDIR" \
      TMP_SUBDIR="$TMP_SUBDIR" \
      MIN_FREE_GB="$MIN_FREE_GB" \
      INPUT_TIMESTEP="$INPUT_TIMESTEP" \
      INPUT_LAYOUT="$INPUT_LAYOUT" \
      sbatch --parsable \
      --job-name="glorys_${v}_${y}" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} YEAR=${y} as jobid=${jid}"
  done
done

echo "Done."
