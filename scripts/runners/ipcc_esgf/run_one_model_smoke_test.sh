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
#    - Keep each stage separate so jobs can finish before the next stage starts
#
#  Intended use:
#    Run STEP=... one stage at a time on the cluster. Do not use STEP=all unless
#    the previous stage outputs already exist, because the underlying runners
#    submit Slurm jobs but do not wait for job completion.
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

Run one step at a time, waiting for Slurm jobs from each step to finish:

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
    monthly_step
    audit_step
    vertical_step
    climatology_step
    delta_step
    add_step
    ;;
  *)
    echo "ERROR: STEP must be one of: plan, monthly, audit, vertical, climatology, delta, add, all"
    exit 1
    ;;
esac
