#!/usr/bin/env bash
# ==============================================================================
#  Audit curated ocean downscaling product values
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Inspect final curated future NetCDF products without modifying them
#    - Compute coarse sanity statistics: finite cell count, min, max, and mean
#    - Write a CSV report for cross-model/scenario/window review
# ==============================================================================

set -euo pipefail
shopt -s nullglob

PRODUCT_ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
OUT_FILE="${OUT_FILE:-data/manifests/future_product_value_audit_0p05.csv}"
FUTURE_MODELS="${FUTURE_MODELS:-auto}"
EXCLUDE_FUTURE_MODELS="${EXCLUDE_FUTURE_MODELS:-cesm_f09_g16 legacy_downscaled_rcp85}"
SCENARIOS="${SCENARIOS:-auto}"
VARS="${VARS:-auto}"
WINDOWS="${WINDOWS:-auto}"
RESOLUTIONS="${RESOLUTIONS:-0p05}"
INCLUDE_ENSEMBLE="${INCLUDE_ENSEMBLE:-yes}"
MAX_FILES="${MAX_FILES:-}"
PROGRESS_EVERY="${PROGRESS_EVERY:-1}"

for required_cmd in find sort awk cdo; do
  if ! command -v "${required_cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found in PATH: ${required_cmd}" >&2
    exit 1
  fi
done

if [[ ! -d "${PRODUCT_ROOT}/future" ]]; then
  echo "ERROR: Future product root does not exist: ${PRODUCT_ROOT}/future" >&2
  exit 1
fi

if [[ -n "${MAX_FILES}" ]] && ! [[ "${MAX_FILES}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: MAX_FILES must be a positive integer when set" >&2
  exit 1
fi

if ! [[ "${PROGRESS_EVERY}" =~ ^[0-9]+$ ]] || [[ "${PROGRESS_EVERY}" -eq 0 ]]; then
  echo "ERROR: PROGRESS_EVERY must be a positive integer" >&2
  exit 1
fi

read -r -a FUTURE_MODEL_LIST <<< "${FUTURE_MODELS}"
read -r -a EXCLUDE_MODEL_LIST <<< "${EXCLUDE_FUTURE_MODELS}"
read -r -a SCENARIO_LIST <<< "${SCENARIOS}"
read -r -a VAR_LIST <<< "${VARS}"
read -r -a WINDOW_LIST <<< "${WINDOWS}"
read -r -a RESOLUTION_LIST <<< "${RESOLUTIONS}"

contains_word() {
  local needle="$1"
  shift
  local candidate

  if (( $# == 0 )); then
    return 0
  fi

  for candidate in "$@"; do
    if [[ "${candidate}" == "${needle}" ]]; then
      return 0
    fi
  done

  return 1
}

csv_quote() {
  local value="${1:-}"
  value="${value//\"/\"\"}"
  printf '"%s"' "${value}"
}

passes_filter() {
  local value="$1"
  local filter_text="$2"
  shift 2

  if [[ "${filter_text}" == "auto" ]]; then
    return 0
  fi

  contains_word "${value}" "$@"
}

cdo_stat() {
  local stat="$1"
  local var="$2"
  local file="$3"

  case "${stat}" in
    ncells)
      cdo -s output -fldsum -gtc,-1e30 -selname,"${var}" "${file}" \
        | awk '{for(i=1;i<=NF;i++) s+=$i} END{print s+0}'
      ;;
    min)
      cdo -s output -fldmin -selname,"${var}" "${file}" \
        | awk 'BEGIN{m=""} {for(i=1;i<=NF;i++) if($i!="nan" && (m=="" || $i<m)) m=$i} END{print m}'
      ;;
    max)
      cdo -s output -fldmax -selname,"${var}" "${file}" \
        | awk 'BEGIN{m=""} {for(i=1;i<=NF;i++) if($i!="nan" && (m=="" || $i>m)) m=$i} END{print m}'
      ;;
    mean)
      cdo -s output -fldmean -selname,"${var}" "${file}" \
        | awk '{for(i=1;i<=NF;i++) if($i!="nan"){s+=$i; n++}} END{if(n>0) print s/n; else print ""}'
      ;;
    *)
      echo "ERROR: Unknown stat: ${stat}" >&2
      return 1
      ;;
  esac
}

mkdir -p "$(dirname "${OUT_FILE}")"

tmp_files="$(mktemp)"
trap 'rm -f "${tmp_files}"' EXIT

find "${PRODUCT_ROOT}/future" -path "*/0p05/*.nc" -type f | sort > "${tmp_files}"

{
  echo "group,model,member_or_stat,scenario,var,window,resolution,file,ncells,min,max,mean"

  inspected=0
  while IFS= read -r file; do
    rel="${file#${PRODUCT_ROOT}/future/}"
    IFS=/ read -r part1 part2 part3 part4 part5 part6 _rest <<< "${rel}"

    if [[ "${part1}" == "ensemble" ]]; then
      [[ "${INCLUDE_ENSEMBLE}" == "yes" ]] || continue
      group="ensemble"
      model="ensemble"
      member_or_stat="${part2}"
      scenario="${part3}"
      var="${part4}"
      window="${part5}"
      resolution="${part6}"
    else
      group="model"
      model="${part1}"
      member_or_stat="${part2}"
      scenario="${part3}"
      var="${part4}"
      window="${part5}"
      resolution="${part6}"
    fi

    contains_word "${model}" "${EXCLUDE_MODEL_LIST[@]}" && continue
    passes_filter "${model}" "${FUTURE_MODELS}" "${FUTURE_MODEL_LIST[@]}" || continue
    passes_filter "${scenario}" "${SCENARIOS}" "${SCENARIO_LIST[@]}" || continue
    passes_filter "${var}" "${VARS}" "${VAR_LIST[@]}" || continue
    passes_filter "${window}" "${WINDOWS}" "${WINDOW_LIST[@]}" || continue
    passes_filter "${resolution}" "${RESOLUTIONS}" "${RESOLUTION_LIST[@]}" || continue

    inspected=$((inspected + 1))
    if (( inspected % PROGRESS_EVERY == 0 )); then
      echo "[AUDIT] ${inspected}: ${group} ${model} ${member_or_stat} ${scenario} ${var} ${window} ${resolution}" >&2
    fi

    ncells="$(cdo_stat ncells "${var}" "${file}")"
    min_value="$(cdo_stat min "${var}" "${file}")"
    max_value="$(cdo_stat max "${var}" "${file}")"
    mean_value="$(cdo_stat mean "${var}" "${file}")"

    csv_quote "${group}"; printf ','
    csv_quote "${model}"; printf ','
    csv_quote "${member_or_stat}"; printf ','
    csv_quote "${scenario}"; printf ','
    csv_quote "${var}"; printf ','
    csv_quote "${window}"; printf ','
    csv_quote "${resolution}"; printf ','
    csv_quote "${file}"; printf ','
    printf '%s,%s,%s,%s\n' "${ncells}" "${min_value}" "${max_value}" "${mean_value}"

    if [[ -n "${MAX_FILES}" ]] && (( inspected >= MAX_FILES )); then
      break
    fi
  done < "${tmp_files}"
} > "${OUT_FILE}"

echo "Wrote future product value audit: ${OUT_FILE}"
echo "Files inspected: $(( $(wc -l < "${OUT_FILE}") - 1 ))"
wc -l "${OUT_FILE}"
