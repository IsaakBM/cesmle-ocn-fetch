#!/usr/bin/env bash
# ==============================================================================
#  One-model IPCC/ESGF smoke-test helper
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Purpose:
#    - Run one small model/scenario/variable subset through the pipeline
#    - Exercise the main workflow branches before scaling to all models
#    - Validate the migrated /home/SB5 default roots before using legacy aliases
#    - Keep each stage separate so jobs can finish before the next stage starts
#
#  Intended use:
#    Run STEP=preflight first on the cluster. Then run STEP=... one stage at a
#    time. Do not use STEP=all unless the previous stage outputs already exist,
#    because the underlying runners submit Slurm jobs but do not wait for job
#    completion.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

SMOKE_MODEL="${SMOKE_MODEL:-CNRM-ESM2-1}"
SMOKE_SCENARIO="${SMOKE_SCENARIO:-ssp585}"
SMOKE_VARS="${SMOKE_VARS:-thetao chl siconc}"
SMOKE_WINDOWS="${SMOKE_WINDOWS:-2050-2060}"
SMOKE_MEMBER="${SMOKE_MEMBER:-auto}"
STEP="${STEP:-plan}"
RUN="${RUN:-no}"
MAX_GROUPS="${MAX_GROUPS:-}"
COMPUTE_STATS="${COMPUTE_STATS:-no}"
IPCC_ESGF_ROOT="${IPCC_ESGF_ROOT:-/home/SB5/ipcc_esgf}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/reanalysis/glorys12v1/monthly_0p05}"
HINDCAST_ROOT="${HINDCAST_ROOT:-/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast}"
HINDCAST_0P25_ROOT="${HINDCAST_0P25_ROOT:-/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25}"
TARGET_REF_FILE="${TARGET_REF_FILE:-${GLORYS_ROOT}/thetao/parts/glorys12v1_thetao_200601.monmean.0p05.nc}"

case "${RUN}" in
  yes|no) ;;
  *)
    echo "ERROR: RUN must be yes or no"
    exit 1
    ;;
esac

run_or_print() {
  local label="$1"
  shift

  echo
  echo "== ${label} =="
  printf 'cd %q\n' "${REPO_ROOT}"
  printf '%q ' "$@"
  printf '\n'

  if [[ "${RUN}" == "yes" ]]; then
    (cd "${REPO_ROOT}" && "$@")
  fi
}

contains_word() {
  local needle="$1"
  shift
  local candidate

  for candidate in "$@"; do
    [[ "$candidate" == "$needle" ]] && return 0
  done
  return 1
}

require_dir() {
  local label="$1"
  local path="$2"

  if [[ -d "$path" ]]; then
    echo "[OK] ${label}: ${path}"
    return 0
  fi

  echo "[MISSING] ${label}: ${path}" >&2
  return 1
}

require_file() {
  local label="$1"
  local path="$2"

  if [[ -f "$path" ]]; then
    echo "[OK] ${label}: ${path}"
    return 0
  fi

  echo "[MISSING] ${label}: ${path}" >&2
  return 1
}

sample_file_count() {
  local path="$1"
  local glob="${2:-*.nc}"

  find "$path" -maxdepth 1 -type f -name "$glob" 2>/dev/null | wc -l | tr -d ' '
}

find_first_dir() {
  local root="$1"
  local pattern="$2"

  [[ -d "$root" ]] || return 0
  find "$root" -path "$pattern" -type d 2>/dev/null | head -n 1
}

preflight_step() {
  local failed=0
  local ipcc_root="${IPCC_ESGF_ROOT}/monthly_1deg"
  local downloads_root="${IPCC_ESGF_ROOT}/downloads"
  local baseline_file
  local parts_dir
  local clim_dir
  local delta_dir
  local download_dir

  read -r -a smoke_var_list <<< "${SMOKE_VARS}"

  echo "Preflight for one-model storage-layout smoke test"
  echo
  echo "Model    : ${SMOKE_MODEL}"
  echo "Scenario : ${SMOKE_SCENARIO}"
  echo "Variables: ${SMOKE_VARS}"
  echo "Windows  : ${SMOKE_WINDOWS}"
  echo "Member   : ${SMOKE_MEMBER}"
  echo "IPCC/ESGF: ${IPCC_ESGF_ROOT}"
  echo "GLORYS   : ${GLORYS_ROOT}"
  echo "Hindcast : ${HINDCAST_ROOT}"
  echo

  require_dir "IPCC downloads root" "${downloads_root}" || failed=1
  require_dir "IPCC monthly root" "${ipcc_root}" || failed=1
  require_dir "GLORYS root" "${GLORYS_ROOT}" || failed=1
  require_dir "Hindcast GLORYS-coast root" "${HINDCAST_ROOT}" || failed=1
  require_dir "Hindcast 0p25 root" "${HINDCAST_0P25_ROOT}" || failed=1
  require_file "GLORYS target reference" "${TARGET_REF_FILE}" || failed=1
  require_file "GLORYS grid" "${GLORYS_ROOT}/grid_0p05_global.txt" || failed=1
  require_file "Hindcast 0p25 grid" "${HINDCAST_0P25_ROOT}/grid_0p25_global.txt" || failed=1

  for var in "${smoke_var_list[@]}"; do
    echo
    echo "Variable: ${var}"
    download_dir="$(find_first_dir "${downloads_root}/${SMOKE_MODEL}" "*/historical/${var}")"
    if [[ -z "${download_dir}" ]]; then
      echo "[WARN] No historical download dir found for ${SMOKE_MODEL} ${var} under ${downloads_root}"
    else
      echo "[OK] historical downloads: ${download_dir} files=$(sample_file_count "${download_dir}")"
    fi

    parts_dir="$(find_first_dir "${ipcc_root}/${SMOKE_MODEL}" "*/historical/${var}/parts")"
    if [[ -z "${parts_dir}" ]]; then
      echo "[WARN] No historical monthly parts dir found yet for ${SMOKE_MODEL} ${var}"
    else
      echo "[OK] historical parts: ${parts_dir} files=$(sample_file_count "${parts_dir}")"
    fi

    clim_dir="$(find_first_dir "${ipcc_root}/${SMOKE_MODEL}" "*/${SMOKE_SCENARIO}/${var}/clim_windows")"
    if [[ -z "${clim_dir}" ]]; then
      echo "[WARN] No future climatology dir found yet for ${SMOKE_MODEL} ${SMOKE_SCENARIO} ${var}"
    else
      echo "[OK] future climatologies: ${clim_dir} files=$(sample_file_count "${clim_dir}")"
    fi

    if contains_word "$var" thetao so uo vo zos mlotst siconc; then
      baseline_file="${GLORYS_ROOT}/${var}/clim_windows/glorys12v1_${var}_clim_2006-2014.nc"
      delta_dir="$(find_first_dir "${ipcc_root}/${SMOKE_MODEL}" "*/${SMOKE_SCENARIO}/${var}/delta_windows_0p05")"
    elif contains_word "$var" chl o2 ph; then
      baseline_file="${HINDCAST_ROOT}/${var}/clim_windows/global_ocean_biogeochemistry_hindcast_${var}_clim_2006-2014_grid_0p05_global.nc"
      delta_dir="$(find_first_dir "${ipcc_root}/${SMOKE_MODEL}" "*/${SMOKE_SCENARIO}/${var}/delta_windows_0p25")"
    else
      baseline_file=""
      delta_dir=""
      echo "[WARN] No trusted baseline family configured for ${var}; it may stop at delta stage."
    fi

    if [[ -n "${baseline_file}" ]]; then
      require_file "trusted baseline for ${var}" "${baseline_file}" || failed=1
    fi

    if [[ -z "${delta_dir}" ]]; then
      echo "[WARN] No final delta dir found yet for ${SMOKE_MODEL} ${SMOKE_SCENARIO} ${var}"
    else
      echo "[OK] final delta dir: ${delta_dir} files=$(sample_file_count "${delta_dir}")"
    fi
  done

  echo
  if [[ "${failed}" -ne 0 ]]; then
    echo "Preflight failed: at least one required migrated root or baseline file is missing." >&2
    return 1
  fi

  echo "Preflight passed for required migrated roots. Warnings are expected before later pipeline stages have run."
}

monthly_step() {
  run_or_print "monthly standardize/regrid: historical + ${SMOKE_SCENARIO}" \
    env \
    MODELS="${SMOKE_MODEL}" \
    SCENARIOS="historical ${SMOKE_SCENARIO}" \
    VARS="${SMOKE_VARS}" \
    MEMBER="${SMOKE_MEMBER}" \
    bash scripts/runners/ipcc_esgf/run_temporal_aggregate_regrid.sh
}

audit_step() {
  run_or_print "unit/depth audit on standardized monthly parts" \
    env \
    MODELS="${SMOKE_MODEL}" \
    SCENARIOS="historical ${SMOKE_SCENARIO}" \
    VARS="${SMOKE_VARS}" \
    MEMBERS="${SMOKE_MEMBER}" \
    FILE_STAGE="parts" \
    COMPUTE_STATS="${COMPUTE_STATS}" \
    MAX_GROUPS="${MAX_GROUPS}" \
    GLORYS_ROOT="${GLORYS_ROOT}" \
    HINDCAST_ROOT="${HINDCAST_ROOT}" \
    OUT_FILE="data/manifests/unit_depth_audit_${SMOKE_MODEL}_${SMOKE_SCENARIO}_smoke.csv" \
    bash scripts/tools/audit_units_and_depths.sh
}

vertical_step() {
  run_or_print "vertical interpolation for 3D variables only" \
    env \
    MODELS="${SMOKE_MODEL}" \
    SCENARIOS="historical ${SMOKE_SCENARIO}" \
    VARS="${SMOKE_VARS}" \
    MEMBER="${SMOKE_MEMBER}" \
    TARGET_REF_FILE="${TARGET_REF_FILE}" \
    bash scripts/runners/ipcc_esgf/run_vertical_interpolate_to_reference.sh
}

climatology_step() {
  run_or_print "climatology windows: baseline + ${SMOKE_WINDOWS}" \
    env \
    MODELS="${SMOKE_MODEL}" \
    SCENARIOS="historical ${SMOKE_SCENARIO}" \
    VARS="${SMOKE_VARS}" \
    MEMBER="${SMOKE_MEMBER}" \
    WINDOWS="baseline ${SMOKE_WINDOWS}" \
    bash scripts/runners/ipcc_esgf/run_climatology_window.sh
}

delta_step() {
  run_or_print "future-minus-historical deltas: ${SMOKE_WINDOWS}" \
    env \
    MODELS="${SMOKE_MODEL}" \
    SCENARIOS="${SMOKE_SCENARIO}" \
    VARS="${SMOKE_VARS}" \
    MEMBER="${SMOKE_MEMBER}" \
    WINDOWS="${SMOKE_WINDOWS}" \
    bash scripts/runners/ipcc_esgf/run_delta_from_climatologies.sh
}

add_step() {
  run_or_print "add deltas to trusted baselines: ${SMOKE_WINDOWS}" \
    env \
    MODELS="${SMOKE_MODEL}" \
    SCENARIOS="${SMOKE_SCENARIO}" \
    VARS="${SMOKE_VARS}" \
    MEMBER="${SMOKE_MEMBER}" \
    WINDOWS="${SMOKE_WINDOWS}" \
    GLORYS_ROOT="${GLORYS_ROOT}" \
    HINDCAST_ROOT="${HINDCAST_ROOT}" \
    REGRID_GRIDFILE="${HINDCAST_0P25_ROOT}/grid_0p25_global.txt" \
    bash scripts/runners/ipcc_esgf_to_hindcast/run_add_anomaly_to_baseline_with_coastal_fill.sh
}

print_plan() {
  cat <<EOF
One-model smoke-test plan

Model    : ${SMOKE_MODEL}
Scenario : ${SMOKE_SCENARIO}
Variables: ${SMOKE_VARS}
Windows  : ${SMOKE_WINDOWS}
Member   : ${SMOKE_MEMBER}
GLORYS   : ${GLORYS_ROOT}
Hindcast : ${HINDCAST_ROOT}

Run one step at a time, waiting for Slurm jobs from each step to finish:

  STEP=preflight    bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
  RUN=yes STEP=monthly      bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
  RUN=yes STEP=audit        bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
  RUN=yes STEP=vertical     bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
  RUN=yes STEP=climatology  bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
  RUN=yes STEP=delta        bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh
  RUN=yes STEP=add          bash scripts/runners/ipcc_esgf/run_one_model_smoke_test.sh

Use RUN=no, the default, to print the command without running it.
EOF
}

case "${STEP}" in
  plan)
    print_plan
    ;;
  preflight)
    preflight_step
    ;;
  monthly)
    monthly_step
    ;;
  audit)
    audit_step
    ;;
  vertical)
    vertical_step
    ;;
  climatology)
    climatology_step
    ;;
  delta)
    delta_step
    ;;
  add)
    add_step
    ;;
  all)
    preflight_step
    monthly_step
    audit_step
    vertical_step
    climatology_step
    delta_step
    add_step
    ;;
  *)
    echo "ERROR: STEP must be one of: plan, preflight, monthly, audit, vertical, climatology, delta, add, all"
    exit 1
    ;;
esac
