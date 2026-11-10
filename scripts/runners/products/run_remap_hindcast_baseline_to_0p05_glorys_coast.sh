#!/usr/bin/env bash
# ==============================================================================
#  Runner for deriving 0.05 hindcast baselines with GLORYS coastline filling
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_SCRIPT="${SCRIPT_DIR}/../../tools/remap_hindcast_baseline_to_0p05_glorys_coast.sh"
LOG_DIR="${LOG_DIR:-/home/sandbox-sparc/cesmle-ocn-fetch/logs}"

IN_ROOT="${IN_ROOT:-/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast}"
GRIDFILE="${GRIDFILE:-/home/SB5/reanalysis/glorys12v1/monthly_0p05/grid_0p05_global.txt}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/reanalysis/glorys12v1/monthly_0p05}"
CLIMATOLOGY_MODE="${CLIMATOLOGY_MODE:-whole}"
BASELINE_TAG="${BASELINE_TAG:-2006-2014}"
BASELINE_SCRATCH_ROOT="${BASELINE_SCRATCH_ROOT:-}"
case "$CLIMATOLOGY_MODE" in
  whole) CLIM_STAGE=clim_windows; field=month ;;
  monthly) CLIM_STAGE=clim_monthly; field=month ;;
  seasonal) CLIM_STAGE=clim_seasonal; field=season ;;
  *) echo "ERROR: CLIMATOLOGY_MODE must be whole, monthly or seasonal" >&2; exit 1 ;;
esac
if [[ "$CLIMATOLOGY_MODE" != whole && -z "$BASELINE_SCRATCH_ROOT" ]]; then
  echo "ERROR: ${CLIMATOLOGY_MODE^} coastal baselines require BASELINE_SCRATCH_ROOT" >&2
  exit 1
fi
default_mask_template="${GLORYS_ROOT}/thetao/${CLIM_STAGE/clim_windows/clim_monthly}/glorys12v1_thetao_clim_${field}_{${field}}_${BASELINE_TAG}.nc"
COASTAL_MASK_FILE_TEMPLATE="${COASTAL_MASK_FILE_TEMPLATE:-$default_mask_template}"
COASTAL_MASK_FILE="${COASTAL_MASK_FILE:-${GLORYS_ROOT}/thetao/clim_windows/glorys12v1_thetao_clim_2006-2014.nc}"
COASTAL_MASK_VAR="${COASTAL_MASK_VAR:-thetao}"
COASTAL_FILL_METHOD="${COASTAL_FILL_METHOD:-distance_weighted}"
COASTAL_FILL_MAX_STEPS="${COASTAL_FILL_MAX_STEPS:-12}"
COASTAL_FILL_WEIGHT_POWER="${COASTAL_FILL_WEIGHT_POWER:-2.0}"
COASTAL_FILL_MIN_DONORS="${COASTAL_FILL_MIN_DONORS:-4}"
COASTAL_FILL_REQUIRE_COMPLETE="${COASTAL_FILL_REQUIRE_COMPLETE:-yes}"
METHOD="${METHOD:-auto}"
AUTO_METHOD_DEFAULT="${AUTO_METHOD_DEFAULT:-remapbil}"
AUTO_METHOD_CURVILINEAR="${AUTO_METHOD_CURVILINEAR:-remapdis}"
OVERWRITE="${OVERWRITE:-yes}"
VARS="${VARS:-}"

PARTITION="${PARTITION:-grit_nodes}"
NODES="${NODES:-1}"
NTASKS="${NTASKS:-1}"
CPUS_PER_TASK="${CPUS_PER_TASK:-4}"
MEMORY="${MEMORY:-256G}"
WALLTIME="${WALLTIME:-2-00:00:00}"
NPROC="${NPROC:-${CPUS_PER_TASK}}"
if [[ "$CLIMATOLOGY_MODE" != whole ]]; then
  # Three variables run independently, but avoid concurrent full 0.05-degree
  # scientific arrays within a single job's existing 256G memory allocation.
  NPROC=1
fi
EXCLUDE_NODES="${EXCLUDE_NODES:-${SBATCH_EXCLUDE:-}}"

mkdir -p "${LOG_DIR}"

if [[ ! -x "${TOOL_SCRIPT}" ]]; then
  echo "ERROR: Tool script not found or not executable: ${TOOL_SCRIPT}"
  exit 1
fi

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ -z "${VARS}" ]]; then
  mapfile -t VAR_LIST < <(
    find "${IN_ROOT}" -mindepth 1 -maxdepth 1 -type d \
      | while read -r d; do
          if [[ -d "${d}/${CLIM_STAGE}" ]]; then
            basename "${d}"
          fi
        done \
      | sort
  )
else
  read -r -a VAR_LIST <<< "${VARS}"
fi

if (( ${#VAR_LIST[@]} == 0 )); then
  echo "ERROR: No variable directories found under: ${IN_ROOT}"
  exit 1
fi

if [[ "$CLIMATOLOGY_MODE" != whole ]]; then
  CHECK_ROOT="$IN_ROOT" CHECK_VARS="${VAR_LIST[*]}" CHECK_TAG="$BASELINE_TAG" \
  CHECK_MASK_TEMPLATE="$COASTAL_MASK_FILE_TEMPLATE" CHECK_GRID="$GRIDFILE" \
  python3 - "$CLIMATOLOGY_MODE" "$CLIM_STAGE" "$field" <<'PY_BASELINE_PREFLIGHT'
import os
import sys
from pathlib import Path

mode, stage, field = sys.argv[1:]
root = Path(os.environ['CHECK_ROOT'])
tag = os.environ['CHECK_TAG']
mask_template = os.environ['CHECK_MASK_TEMPLATE']
placeholder = '{' + field + '}'
tokens = [f'{month:02d}' for month in range(1, 13)] if mode == 'monthly' else ['DJF', 'MAM', 'JJA', 'SON']
assert Path(os.environ['CHECK_GRID']).is_file(), 'Missing baseline target grid'
assert placeholder in mask_template, f'Mask template must contain {placeholder}'
for var in os.environ['CHECK_VARS'].split():
    for token in tokens:
        source = root/var/stage/f'global_ocean_biogeochemistry_hindcast_{var}_clim_{field}_{token}_{tag}.nc'
        mask = Path(mask_template.replace(placeholder, token))
        assert source.is_file(), f'Missing {mode} baseline input: {source}'
        assert mask.is_file(), f'Missing {mode} GLORYS mask: {mask}'
print(f'{mode.upper()} COASTAL BASELINE INPUT COVERAGE: PASS', flush=True)
PY_BASELINE_PREFLIGHT
fi

echo "Submitting hindcast 0.25 -> 0.05 GLORYS-coast jobs by variable:"
echo "IN ROOT          : ${IN_ROOT}"
echo "OUT ROOT         : ${OUT_ROOT}"
echo "VARS             : ${VAR_LIST[*]}"
echo "GRIDFILE         : ${GRIDFILE}"
echo "COASTAL MASK     : ${COASTAL_MASK_FILE}"
echo "COASTAL MASK VAR : ${COASTAL_MASK_VAR}"
echo "FILL METHOD      : ${COASTAL_FILL_METHOD}"
echo "FILL STEPS       : ${COASTAL_FILL_MAX_STEPS}"
echo "FILL POWER       : ${COASTAL_FILL_WEIGHT_POWER}"
echo "FILL DONORS      : ${COASTAL_FILL_MIN_DONORS}"
echo "REQUIRE COMPLETE : ${COASTAL_FILL_REQUIRE_COMPLETE}"
echo "METHOD           : ${METHOD}"
echo "OVERWRITE        : ${OVERWRITE}"
echo "EXCLUDE NODES    : ${EXCLUDE_NODES:-<none>}"

for var in "${VAR_LIST[@]}"; do
  sbatch_args=()
  if [[ -n "${EXCLUDE_NODES}" ]]; then
    sbatch_args+=(--exclude="${EXCLUDE_NODES}")
  fi

  jid=$(
    sbatch --parsable \
      --job-name="hind05gc_${var}" \
      --partition="${PARTITION}" \
      --nodes="${NODES}" \
      --ntasks="${NTASKS}" \
      --cpus-per-task="${CPUS_PER_TASK}" \
      --mem="${MEMORY}" \
      --time="${WALLTIME}" \
      --output="${LOG_DIR}/hindcast_0p05_glorys_coast_${var}_%j.out" \
      --error="${LOG_DIR}/hindcast_0p05_glorys_coast_${var}_%j.err" \
      ${sbatch_args[@]+"${sbatch_args[@]}"} \
      --export="ALL,IN_ROOT=${IN_ROOT},OUT_ROOT=${OUT_ROOT},GRIDFILE=${GRIDFILE},VARS=${var},METHOD=${METHOD},AUTO_METHOD_DEFAULT=${AUTO_METHOD_DEFAULT},AUTO_METHOD_CURVILINEAR=${AUTO_METHOD_CURVILINEAR},COASTAL_MASK_FILE=${COASTAL_MASK_FILE},COASTAL_MASK_VAR=${COASTAL_MASK_VAR},COASTAL_FILL_METHOD=${COASTAL_FILL_METHOD},COASTAL_FILL_MAX_STEPS=${COASTAL_FILL_MAX_STEPS},COASTAL_FILL_WEIGHT_POWER=${COASTAL_FILL_WEIGHT_POWER},COASTAL_FILL_MIN_DONORS=${COASTAL_FILL_MIN_DONORS},COASTAL_FILL_REQUIRE_COMPLETE=${COASTAL_FILL_REQUIRE_COMPLETE},OVERWRITE=${OVERWRITE},NPROC=${NPROC},CLIMATOLOGY_MODE=${CLIMATOLOGY_MODE},BASELINE_TAG=${BASELINE_TAG},BASELINE_SCRATCH_ROOT=${BASELINE_SCRATCH_ROOT},COASTAL_MASK_FILE_TEMPLATE=${COASTAL_MASK_FILE_TEMPLATE}" \
      --wrap="bash '${TOOL_SCRIPT}'"
  )
  echo "  submitted VAR=${var} as jobid=${jid}"
done

echo "Done."
