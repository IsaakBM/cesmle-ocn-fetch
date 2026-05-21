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
#   - The generic worker is run in auto remap mode:
#       * curvilinear/unstructured sources -> remapdis
#       * regular lon/lat sources          -> remapbil
#     This keeps the runner safe for institutions that do not show the seam
#     artifact while still fixing the problematic curvilinear cases.
#   - Expected input layout:
#       /home/SB5/ipcc_esgf_downloads/<scenario>/<variable>/*.nc
#     Output layout:
#       /home/SB5/ipcc_esgf_monthly_1deg/<model>/<scenario>/<variable>/parts/*.nc
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/../../core/temporal_aggregate_regrid.slurm.sh"
DISCOVERY_LIB="${SCRIPT_DIR}/../../lib/ipcc_esgf_discovery.sh"

# shellcheck source=../../lib/ipcc_esgf_discovery.sh
source "${DISCOVERY_LIB}"

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
METHOD="auto"
AUTO_METHOD_DEFAULT="remapbil"
AUTO_METHOD_CURVILINEAR="remapdis"
FILE_GLOB="*.nc"
PARTS_SUBDIR="parts"
TMP_SUBDIR="tmp"
MIN_FREE_GB=40
INPUT_LAYOUT="timeseries"
INPUT_TIMESTEP="monthly"
MEMBER="${MEMBER:-auto}"

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
mapfile -t DISCOVERED_GROUPS < <(ipcc_esgf_discover_download_groups "${INROOT_BASE}" "${FILE_GLOB}" | sort -u)
declare -A SEEN_GROUPS=()

if (( ${#DISCOVERED_GROUPS[@]} == 0 )); then
  echo "ERROR: No CMIP-style ESGF files discovered under: ${INROOT_BASE}"
  exit 1
fi

for group in "${DISCOVERED_GROUPS[@]}"; do
  IFS=$'\t' read -r model scen v member table_id source_grid <<< "$group"
  group_key="${model}|${scen}|${v}|${member}"

  if [[ -n "${SEEN_GROUPS[$group_key]:-}" ]]; then
    continue
  fi
  SEEN_GROUPS[$group_key]=1

  if [[ ! " ${VARS[*]} " == *" ${v} "* ]]; then
    continue
  fi

  if [[ "${MEMBER}" != "auto" && "${member}" != "${MEMBER}" ]]; then
    continue
  fi

  INROOT="${INROOT_BASE}/${scen}/${v}"
  file_glob="${v}_*_${model}_${scen}_${member}_*.nc"
  if [[ ! -d "$INROOT" ]]; then
    first_file="$(find "${INROOT_BASE}" -type f -name "$file_glob" | sort | head -n 1)"
    if [[ -z "$first_file" ]]; then
      echo "  WARN: No input files found for MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v}"
      continue
    fi
    INROOT="$(dirname "$first_file")"
  fi

  resolved_member="$(ipcc_esgf_resolve_member "$INROOT" "${v}_*_${model}_${scen}_*_*.nc")" || {
    status=$?
    [[ "$status" -eq 2 ]] && continue
    exit "$status"
  }
  if [[ "$resolved_member" != "$member" ]]; then
    continue
  fi

  OUTROOT="${OUTROOT_BASE}/${model}/${scen}"
  job_label="${DATASET_LABEL}_${model}_${scen}_${member}"

  jid=$(DATASET_LABEL="${job_label}" \
      VAR="$v" \
      INROOT="$INROOT" \
      OUTROOT="$OUTROOT" \
      GRIDFILE="$GRIDFILE" \
      INPUT_LAYOUT="$INPUT_LAYOUT" \
      INPUT_TIMESTEP="$INPUT_TIMESTEP" \
      METHOD="$METHOD" \
      AUTO_METHOD_DEFAULT="$AUTO_METHOD_DEFAULT" \
      AUTO_METHOD_CURVILINEAR="$AUTO_METHOD_CURVILINEAR" \
      FILE_GLOB="$file_glob" \
      PARTS_SUBDIR="$PARTS_SUBDIR" \
      TMP_SUBDIR="$TMP_SUBDIR" \
      MIN_FREE_GB="$MIN_FREE_GB" \
      sbatch --parsable \
      --job-name="ipcc_${scen}_${v}" \
      "$CORE_SCRIPT")
  echo "  submitted MODEL=${model} SCENARIO=${scen} MEMBER=${member} VAR=${v} TABLE=${table_id} GRID=${source_grid} as jobid=${jid}"
done

echo "Done."
