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
#       /home/SB5/reanalysis/glorys12v1/downloads/<year>/<month>/*.nc*
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/temporal_aggregate_regrid.slurm.sh"

# ------------------------------------------------------------------------------
# Control variables here, one at a time if preferred
# ------------------------------------------------------------------------------
VARS_DEFAULT=(
  thetao
  so
  mlotst
  uo
  vo
  zos
  bottomT
  siconc
)
read -r -a VARS <<< "${VARS:-${VARS_DEFAULT[*]}}"

YEARS_DEFAULT=(
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
read -r -a YEARS <<< "${YEARS:-${YEARS_DEFAULT[*]}}"
MONTHS="${MONTHS:-01 02 03 04 05 06 07 08 09 10 11 12}"
EXCLUDE_NODES="${EXCLUDE_NODES:-}"
MEM_3D="${MEM_3D:-192G}"
MEM_2D="${MEM_2D:-32G}"
WALLTIME="${WALLTIME:-5-00:00:00}"

make_sbatch_extra_args() {
  if [[ -n "$EXCLUDE_NODES" ]]; then
    printf '%s\n' "--exclude=${EXCLUDE_NODES}"
  fi
}

# ------------------------------------------------------------------------------
# Dataset-specific settings
# ------------------------------------------------------------------------------
DATASET_LABEL="glorys12v1"
INROOT="${INROOT:-/home/SB5/reanalysis/glorys12v1/downloads}"
OUTROOT="/home/SB5/reanalysis/glorys12v1/monthly_0p05"
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
  case "$v" in
    mlotst|zos|siconc)
      JOB_MEMORY="$MEM_2D"
      ;;
    *)
      JOB_MEMORY="$MEM_3D"
      ;;
  esac
  echo "Variable: $v"
  echo "  resources: memory=${JOB_MEMORY} walltime=${WALLTIME}"
  for y in "${YEARS[@]}"; do
    mapfile -t sbatch_extra_args < <(make_sbatch_extra_args)
    jid=$(DATASET_LABEL="$DATASET_LABEL" \
      VAR="$v" \
      YEAR="$y" \
      MONTHS="$MONTHS" \
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
      "${sbatch_extra_args[@]}" \
      --job-name="glorys_${v}_${y}" \
      --mem="$JOB_MEMORY" \
      --time="$WALLTIME" \
      "$CORE_SCRIPT")
    echo "  submitted VAR=${v} YEAR=${y} as jobid=${jid}"
  done
done

echo "Done."
