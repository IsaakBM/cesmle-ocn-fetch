#!/usr/bin/env bash
# Shared selection for layer/pelagic Parquet and GeoTIFF submission runners.
# Sourced only; defaults, preflight checks, and sbatch commands stay in runners.
# Inputs: SOURCE_ROOT, INCLUDE_BASELINE, FUTURE_MODELS, EXCLUDE_FUTURE_MODELS,
# FUTURE_MODEL_LIST, EXCLUDE_FUTURE_MODEL_LIST, SPLIT_ENSEMBLE_STATS,
# SPLIT_FUTURE_SCENARIOS. Result: SUBTREES, in the original sorted order.
# Selection and empty-tree fallback semantics are preserved from the runners.

contains_word() {
  local needle="$1"
  shift
  local candidate

  for candidate in "$@"; do
    [[ "${candidate}" == "${needle}" ]] && return 0
  done
  return 1
}

include_subtree() {
  local subtree="$1"
  local rel_path model

  rel_path="${subtree#${SOURCE_ROOT}/}"
  case "${rel_path}" in
    baseline/*)
      [[ "${INCLUDE_BASELINE}" == "yes" ]] || return 1
      return 0
      ;;
    future/*)
      model="${rel_path#future/}"
      model="${model%%/*}"
      if [[ -n "${EXCLUDE_FUTURE_MODELS}" ]] && contains_word "${model}" "${EXCLUDE_FUTURE_MODEL_LIST[@]}"; then
        return 1
      fi
      if [[ "${FUTURE_MODELS}" != "auto" ]] && ! contains_word "${model}" "${FUTURE_MODEL_LIST[@]}"; then
        return 1
      fi
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

select_product_export_subtrees() {
  mapfile -t SUBTREES < <(
    while IFS= read -r subtree; do
      include_subtree "${subtree}" && printf '%s\n' "${subtree}"
    done < <(
      find "${SOURCE_ROOT}/baseline" "${SOURCE_ROOT}/future" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        ! -name 'tmp*' \
        2>/dev/null | sort
    )
  )
  if (( ${#SUBTREES[@]} == 0 )); then
    echo "ERROR: No baseline/future variable directories found under: ${SOURCE_ROOT}"
    exit 1
  fi

  if [[ "${SPLIT_ENSEMBLE_STATS}" == "yes" ]]; then
    expanded_subtrees=()
    for subtree in "${SUBTREES[@]}"; do
      rel_path="${subtree#${SOURCE_ROOT}/}"
      if [[ "${rel_path}" == "future/ensemble" ]]; then
        mapfile -t ensemble_stat_subtrees < <(
          find "${subtree}" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            ! -name 'tmp*' \
            2>/dev/null | sort
        )
        if (( ${#ensemble_stat_subtrees[@]} > 0 )); then
          expanded_subtrees+=("${ensemble_stat_subtrees[@]}")
        else
          expanded_subtrees+=("${subtree}")
        fi
      else
        expanded_subtrees+=("${subtree}")
      fi
    done
    SUBTREES=("${expanded_subtrees[@]}")
  fi

  if [[ "${SPLIT_FUTURE_SCENARIOS}" == "yes" ]]; then
    expanded_subtrees=()
    for subtree in "${SUBTREES[@]}"; do
      rel_path="${subtree#${SOURCE_ROOT}/}"
      if [[ "${rel_path}" == future/* ]]; then
        scenario_depth=2
        if [[ "${rel_path}" == future/ensemble/* ]]; then
          scenario_depth=1
        fi
        mapfile -t scenario_subtrees < <(
          find "${subtree}" \
            -mindepth "${scenario_depth}" \
            -maxdepth "${scenario_depth}" \
            -type d \
            ! -name 'tmp*' \
            2>/dev/null | sort
        )
        if (( ${#scenario_subtrees[@]} > 0 )); then
          expanded_subtrees+=("${scenario_subtrees[@]}")
        else
          expanded_subtrees+=("${subtree}")
        fi
      else
        expanded_subtrees+=("${subtree}")
      fi
    done
    SUBTREES=("${expanded_subtrees[@]}")
  fi
}
