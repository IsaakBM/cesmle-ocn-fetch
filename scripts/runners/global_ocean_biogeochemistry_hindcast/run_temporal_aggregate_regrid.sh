#!/usr/bin/env bash
# ==============================================================================
#  Global Ocean Biogeochemistry Hindcast runner for generic temporal
#  aggregation + regridder
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Runner: submit monthly jobs by year for selected variable(s) using the generic
# temporal aggregation + regrid worker.
#
# Notes:
#   - This runner is allocated to the Global Ocean Biogeochemistry Hindcast
#     dataset family because that is the intended use case for this workflow.
#   - The target grid in this runner is 0.25 x 0.25 degrees.
#   - Adjust the dataset-specific paths and variables below as needed for the
#     actual source dataset on the cluster.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/temporal_aggregate_regrid.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS=(
  chl
  no3
  po4
  si
  o2
  nppv
  fe
  spco2
  ph
  phyc
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
DATASET_LABEL="global_ocean_biogeochemistry_hindcast"
INROOT="/home/sandbox-sparc/cesmle-ocn-fetch/bgc_monthly_0p25"
OUTROOT="/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p25"
GRIDFILE="${OUTROOT}/grid_0p25_global.txt"
METHOD="remapbil"
FILE_GLOB="*.nc*"
PARTS_SUBDIR="parts"
TMP_SUBDIR="tmp"
MIN_FREE_GB=40
INPUT_TIMESTEP="auto"

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs
mkdir -p "$OUTROOT"

if [[ ! -s "$GRIDFILE" ]]; then
  cat > "$GRIDFILE" << 'EOF'
gridtype = lonlat
xsize    = 1440
ysize    = 721
xfirst   = -180.0
xinc     = 0.25
yfirst   = -90.0
yinc     = 0.25
EOF
fi

echo "Submitting monthly jobs by year with generic worker:"
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
      sbatch --parsable \
      --job-name="mm_${v}_${y}" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} YEAR=${y} as jobid=${jid}"
  done
done

echo "Done."
