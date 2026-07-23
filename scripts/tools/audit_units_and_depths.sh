#!/usr/bin/env bash
# ==============================================================================
#  Audit CMIP/IPCC source units and depth coordinates against trusted baselines
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Inspect representative NetCDF files without modifying them
#    - Flag likely depth-unit mismatches before vertical interpolation
#    - Flag likely variable unit/scale mismatches before delta/add workflows
#    - Flag likely final add-stage anomaly scaling and physical bounds needs
#    - Write a CSV report for review before running the full pipeline
#
#  Intended to be run on an HPC login node or Slurm node with cdo and ncdump.
# ==============================================================================

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   IPCC_ROOT      : CMIP/IPCC standardized monthly root
#                    (default: /home/SB5/ipcc_esgf/monthly_1deg)
#   GLORYS_ROOT    : GLORYS baseline root
#                    (default: /home/SB5/glorys12v1_monthly_0p05)
#   HINDCAST_ROOT  : hindcast baseline root on GLORYS coast
#                    (default: /home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast)
#   BASELINE_TAG   : baseline climatology tag
#                    (default: 2006-2014)
#   OUT_FILE       : CSV audit report
#                    (default: data/manifests/unit_depth_audit.csv)
#   MODELS         : optional space-separated model filter
#   MEMBERS        : optional space-separated member/realization filter
#   SCENARIOS      : optional space-separated scenario filter
#   VARS           : optional space-separated variable filter
#   FILE_STAGE     : source stage to inspect: parts | on_glorys | clim_windows
#                    (default: parts)
#   FILE_GLOB      : NetCDF file glob inside each stage directory
#                    (default: *.nc)
#   COMPUTE_STATS  : yes | no, compute first-timestep field min/max
#                    (default: no)
#   MAX_GROUPS     : optional positive integer limit for quick tests
# ==============================================================================

IPCC_ROOT="${IPCC_ROOT:-/home/SB5/ipcc_esgf/monthly_1deg}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/glorys12v1_monthly_0p05}"
HINDCAST_ROOT="${HINDCAST_ROOT:-/home/SB5/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast}"
BASELINE_TAG="${BASELINE_TAG:-2006-2014}"
OUT_FILE="${OUT_FILE:-data/manifests/unit_depth_audit.csv}"
MODELS="${MODELS:-}"
MEMBERS="${MEMBERS:-}"
SCENARIOS="${SCENARIOS:-}"
VARS="${VARS:-thetao so ph o2 chl uo vo zooc zos mlotst siconc}"
FILE_STAGE="${FILE_STAGE:-parts}"
FILE_GLOB="${FILE_GLOB:-*.nc}"
COMPUTE_STATS="${COMPUTE_STATS:-no}"
MAX_GROUPS="${MAX_GROUPS:-}"

GLORYS_BASELINE_VARS="${GLORYS_BASELINE_VARS:-thetao so uo vo zos mlotst siconc}"
HINDCAST_BASELINE_VARS="${HINDCAST_BASELINE_VARS:-chl o2 ph}"

if [[ "${FILE_STAGE}" != "parts" && "${FILE_STAGE}" != "on_glorys" && "${FILE_STAGE}" != "clim_windows" ]]; then
  echo "ERROR: FILE_STAGE must be one of: parts, on_glorys, clim_windows" >&2
  exit 1
fi

if [[ -n "${MAX_GROUPS}" ]] && ! [[ "${MAX_GROUPS}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: MAX_GROUPS must be a positive integer when set" >&2
  exit 1
fi

if [[ "${COMPUTE_STATS}" != "yes" && "${COMPUTE_STATS}" != "no" ]]; then
  echo "ERROR: COMPUTE_STATS must be yes or no" >&2
  exit 1
fi

for required_cmd in find sort awk sed cdo ncdump; do
  if ! command -v "${required_cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found in PATH: ${required_cmd}" >&2
    exit 1
  fi
done

if [[ ! -d "${IPCC_ROOT}" ]]; then
  echo "ERROR: IPCC_ROOT does not exist: ${IPCC_ROOT}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT_FILE}")"

contains_word() {
  local needle="$1"
  shift
  local item

  if (( $# == 0 )); then
    return 0
  fi

  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done

  return 1
}

csv_escape() {
  local value="${1:-}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//\"/\"\"}"
  printf '"%s"' "${value}"
}

csv_row() {
  local first="yes"
  local value

  for value in "$@"; do
    if [[ "${first}" == "yes" ]]; then
      first="no"
    else
      printf ','
    fi
    csv_escape "${value}"
  done
  printf '\n'
}

normalize_units() {
  local units="${1:-}"
  units="$(printf '%s' "${units}" | tr '[:upper:]' '[:lower:]')"
  units="${units//_/ }"
  units="${units//\*\*/^}"
  units="${units// /}"
  printf '%s\n' "${units}"
}

get_attr() {
  local file="$1"
  local var="$2"
  local attr="$3"

  {
    ncdump -h "${file}" 2>/dev/null \
    | awk -v v="${var}" -v a="${attr}" '
      $0 ~ "[[:space:]]" v ":" a "[[:space:]]*=" {
        line = $0
        sub(/^.*=[[:space:]]*/, "", line)
        sub(/[[:space:]]*;[[:space:]]*$/, "", line)
        gsub(/^"/, "", line)
        gsub(/"$/, "", line)
        print line
        exit
      }
    '
  } || true
}

has_var() {
  local file="$1"
  local var="$2"

  ncdump -h "${file}" 2>/dev/null \
    | awk -v v="${var}" '
      $0 ~ "^[[:space:]]*(byte|char|short|int|int64|float|double)[[:space:]]+" v "\\(" {
        found = 1
      }
      END { exit found ? 0 : 1 }
    '
}

pick_data_var() {
  local file="$1"
  local requested="$2"

  if has_var "${file}" "${requested}"; then
    printf '%s\n' "${requested}"
    return 0
  fi

  {
    cdo -s showname "${file}" 2>/dev/null \
    | tr ' ' '\n' \
    | awk 'NF && $1 !~ /(bnds|bounds)$/ {print; exit}'
  } || true
}

pick_zdim() {
  local file="$1"
  local var="$2"
  local header

  header="$(ncdump -h "${file}" 2>/dev/null)"
  {
    printf '%s\n' "${header}" \
    | awk -v v="${var}" '
      $0 ~ "^[[:space:]]*(byte|char|short|int|int64|float|double)[[:space:]]+" v "\\(" {
        line = $0
        sub(/^.*\(/, "", line)
        sub(/\).*$/, "", line)
        n = split(line, dims, /,[[:space:]]*/)
        for (i = 1; i <= n; i++) {
          d = dims[i]
          dl = tolower(d)
          if (dl == "lev" || dl == "depth" || dl == "depth_below_sea" || dl == "z_t" || dl == "olevel") {
            print d
            exit
          }
        }
      }
    '
  } || true
}

levels_min_max() {
  local file="$1"
  local levels

  levels="$({ cdo -s showlevel "${file}" 2>/dev/null | tr ' ' '\n' | awk 'NF'; } || true)"
  if [[ -z "${levels}" ]]; then
    printf ','
    return 0
  fi

  printf '%s\n' "${levels}" \
    | awk '
      NR == 1 { min = $1; max = $1 }
      $1 < min { min = $1 }
      $1 > max { max = $1 }
      END { printf "%s,%s", min, max }
    '
}

field_min_max() {
  local file="$1"
  local var="$2"
  local min_value max_value

  min_value="$(
    {
      cdo -s output -fldmin -seltimestep,1 -selname,"${var}" "${file}" 2>/dev/null \
      | tr ' ' '\n' \
      | awk 'NF && $1 != "nan" {print; exit}'
    } || true
  )"
  max_value="$(
    {
      cdo -s output -fldmax -seltimestep,1 -selname,"${var}" "${file}" 2>/dev/null \
      | tr ' ' '\n' \
      | awk 'NF && $1 != "nan" {print; exit}'
    } || true
  )"

  printf '%s,%s' "${min_value:-}" "${max_value:-}"
}

baseline_target_for_var() {
  local var="$1"

  read -r -a glorys_vars <<< "${GLORYS_BASELINE_VARS}"
  read -r -a hindcast_vars <<< "${HINDCAST_BASELINE_VARS}"

  if contains_word "${var}" "${glorys_vars[@]}"; then
    printf 'glorys\n'
  elif contains_word "${var}" "${hindcast_vars[@]}"; then
    printf 'hindcast\n'
  else
    printf 'none\n'
  fi
}

baseline_file_for_var() {
  local var="$1"
  local target="$2"

  case "${target}" in
    glorys)
      printf '%s/%s/clim_windows/glorys12v1_%s_clim_%s.nc\n' \
        "${GLORYS_ROOT}" "${var}" "${var}" "${BASELINE_TAG}"
      ;;
    hindcast)
      printf '%s/%s/clim_windows/global_ocean_biogeochemistry_hindcast_%s_clim_%s_grid_0p05_global.nc\n' \
        "${HINDCAST_ROOT}" "${var}" "${var}" "${BASELINE_TAG}"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

suggest_z_scale_and_note() {
  local z_units="$1"
  local z_max="$2"
  local units_norm

  units_norm="$(normalize_units "${z_units}")"
  if [[ "${units_norm}" == "cm" || "${units_norm}" == "centimeter" || "${units_norm}" == "centimeters" ]]; then
    printf '0.01,source depth units are centimeters'
  elif [[ -n "${z_max}" ]] && awk -v z="${z_max}" 'BEGIN { exit !(z > 20000) }'; then
    printf '0.01,source depth max is very large; likely centimeters'
  elif [[ -z "${z_max}" ]]; then
    printf ',no vertical levels detected'
  else
    printf '1,source depth appears meter-like'
  fi
}

suggest_var_scale_and_note() {
  local var="$1"
  local source_units="$2"
  local source_min="$3"
  local source_max="$4"
  local baseline_units="$5"
  local baseline_min="$6"
  local baseline_max="$7"
  local su bu

  su="$(normalize_units "${source_units}")"
  bu="$(normalize_units "${baseline_units}")"

  case "${var}" in
    siconc)
      if [[ -n "${source_max}" && -n "${baseline_max}" ]] \
        && awk -v s="${source_max}" -v b="${baseline_max}" 'BEGIN { exit !(s <= 1.5 && b > 2) }'; then
        printf '100,source looks fractional and baseline looks percent'
      elif [[ -n "${source_max}" && -n "${baseline_max}" ]] \
        && awk -v s="${source_max}" -v b="${baseline_max}" 'BEGIN { exit !(s > 2 && b <= 1.5) }'; then
        printf '0.01,source looks percent and baseline looks fractional'
      else
        printf '1,siconc source/baseline range looks compatible or inconclusive'
      fi
      ;;
    thetao)
      if [[ -n "${source_max}" && -n "${baseline_max}" ]] \
        && awk -v s="${source_max}" -v b="${baseline_max}" 'BEGIN { exit !(s > 100 && b < 100) }'; then
        printf 'K_to_C,source looks Kelvin and baseline looks Celsius'
      else
        printf '1,thetao source/baseline range looks compatible or inconclusive'
      fi
      ;;
    uo|vo)
      if [[ "${su}" == *"cms-1"* || "${su}" == *"cm/s"* || "${su}" == *"cmsec-1"* ]]; then
        printf '0.01,source velocity units look like cm/s'
      else
        printf '1,velocity units look compatible or inconclusive'
      fi
      ;;
    o2)
      if [[ "${su}" == *"molm-3"* && "${bu}" == *"mmolm-3"* ]]; then
        printf '1000,source oxygen looks mol/m3 and baseline looks mmol/m3'
      elif [[ "${su}" == *"mmolm-3"* && "${bu}" == *"molm-3"* ]]; then
        printf '0.001,source oxygen looks mmol/m3 and baseline looks mol/m3'
      else
        printf '1,o2 units look compatible or need manual review'
      fi
      ;;
    chl)
      if [[ "${su}" == *"kgm-3"* && ( "${bu}" == *"mgm-3"* || "${bu}" == *"mg/m3"* ) ]]; then
        printf '1000000,source chlorophyll looks kg/m3 and baseline looks mg/m3'
      else
        printf '1,chl uses log-ratio for deltas; still review absolute baseline units'
      fi
      ;;
    ph)
      printf '1,ph should be dimensionless pH; review scale/convention manually'
      ;;
    *)
      if [[ -n "${source_units}" && -n "${baseline_units}" && "${su}" != "${bu}" ]]; then
        printf 'review,source/baseline units differ'
      else
        printf '1,units look compatible or unavailable'
      fi
      ;;
  esac
}

suggest_add_stage_scale_bounds_and_note() {
  local var="$1"
  local source_units="$2"
  local source_min="$3"
  local source_max="$4"
  local baseline_units="$5"
  local baseline_min="$6"
  local baseline_max="$7"
  local baseline_target="$8"
  local su bu anomaly_scale output_bounds status note

  su="$(normalize_units "${source_units}")"
  bu="$(normalize_units "${baseline_units}")"

  anomaly_scale="1"
  output_bounds=""
  status="ok"
  note="no special add-stage scale or bounds inferred"

  case "${var}" in
    siconc)
      if [[ "${bu}" == "1" || "${bu}" == "fraction" || "${bu}" == "unitless" ]] \
        && [[ "${su}" == "%" || "${su}" == "percent" ]]; then
        anomaly_scale="0.01"
        output_bounds="0:1"
        status="scale_and_bounds_required"
        note="target siconc is fraction and source siconc is percent; scale additive anomaly by 0.01 and bound final to [0-1]"
      elif [[ "${bu}" == "%" || "${bu}" == "percent" ]] \
        && [[ "${su}" == "1" || "${su}" == "fraction" || "${su}" == "unitless" ]]; then
        anomaly_scale="100"
        output_bounds="0:100"
        status="scale_and_bounds_required"
        note="target siconc is percent and source siconc is fraction; scale additive anomaly by 100 and bound final to [0-100]"
      elif [[ -n "${source_max}" && -n "${baseline_max}" ]] \
        && awk -v s="${source_max}" -v b="${baseline_max}" 'BEGIN { exit !(s > 2 && b <= 1.5) }'; then
        anomaly_scale="0.01"
        output_bounds="0:1"
        status="scale_and_bounds_required"
        note="target siconc range looks fractional and source range looks percent; scale additive anomaly by 0.01 and bound final to [0-1]"
      elif [[ -n "${source_max}" && -n "${baseline_max}" ]] \
        && awk -v s="${source_max}" -v b="${baseline_max}" 'BEGIN { exit !(s <= 1.5 && b > 2) }'; then
        anomaly_scale="100"
        output_bounds="0:100"
        status="scale_and_bounds_required"
        note="target siconc range looks percent and source range looks fractional; scale additive anomaly by 100 and bound final to [0-100]"
      elif [[ "${bu}" == "1" || "${bu}" == "fraction" || "${bu}" == "unitless" ]]; then
        output_bounds="0:1"
        status="bounds_required"
        note="target siconc appears fractional; bound final to [0-1]"
      elif [[ "${bu}" == "%" || "${bu}" == "percent" ]]; then
        output_bounds="0:100"
        status="bounds_required"
        note="target siconc appears percent; bound final to [0-100]"
      else
        output_bounds="review"
        status="review_add_stage_scale"
        note="could not determine siconc target/source scale from metadata or ranges"
      fi
      ;;
    mlotst)
      output_bounds="0:"
      status="bounds_required"
      note="mixed layer thickness is nonnegative; bound final to >=0"
      ;;
    so)
      output_bounds="0:"
      status="bounds_required"
      note="salinity is nonnegative; bound rare additive-overshoot cells to >=0"
      ;;
    chl)
      if [[ "${baseline_target}" == "hindcast" ]]; then
        output_bounds="0:"
        status="bounds_recommended"
        note="chlorophyll is nonnegative; log-ratio deltas should preserve positivity and final lower bound is scientifically valid if enabled"
      fi
      ;;
    o2)
      output_bounds="0:"
      status="bounds_recommended"
      note="oxygen is nonnegative; review final products for rare additive overshoot"
      ;;
    *)
      ;;
  esac

  printf '%s,%s,%s,%s' "${anomaly_scale}" "${output_bounds}" "${status}" "${note}"
}

status_from_notes() {
  local baseline_target="$1"
  local baseline_file="$2"
  local suggested_z_scale="$3"
  local suggested_var_scale="$4"

  if [[ "${baseline_target}" == "none" ]]; then
    printf 'delta_only'
  elif [[ ! -f "${baseline_file}" ]]; then
    printf 'missing_baseline'
  elif [[ "${suggested_z_scale}" != "1" && -n "${suggested_z_scale}" ]]; then
    printf 'review_depth_units'
  elif [[ "${suggested_var_scale}" != "1" && -n "${suggested_var_scale}" ]]; then
    printf 'review_variable_units'
  else
    printf 'ok_or_review_metadata'
  fi
}

list_values_or_dirs() {
  local root="$1"
  shift
  local filters=("$@")

  if (( ${#filters[@]} > 0 )); then
    printf '%s\n' "${filters[@]}"
    return 0
  fi

  find "${root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

first_stage_file() {
  local stage_dir="$1"

  find "${stage_dir}" -maxdepth 1 -type f -name "${FILE_GLOB}" -print -quit 2>/dev/null
}

read -r -a MODEL_FILTER <<< "${MODELS}"
read -r -a MEMBER_FILTER <<< "${MEMBERS}"
read -r -a SCENARIO_FILTER <<< "${SCENARIOS}"
read -r -a VAR_FILTER <<< "${VARS}"

if [[ "${MEMBERS}" == "auto" ]]; then
  MEMBER_FILTER=()
fi

csv_row \
  model member scenario var source_stage source_file source_data_var source_units \
  source_z_dim source_z_units source_z_min source_z_max source_min source_max \
  baseline_target baseline_file baseline_data_var baseline_units baseline_z_dim \
  baseline_z_units baseline_z_min baseline_z_max baseline_min baseline_max \
  suggested_z_scale suggested_var_scale suggested_anomaly_scale \
  suggested_output_bounds add_stage_status status notes > "${OUT_FILE}"

processed=0

while IFS= read -r model; do
  model_dir="${IPCC_ROOT}/${model}"
  [[ -d "${model_dir}" ]] || continue

  while IFS= read -r member; do
    member_dir="${model_dir}/${member}"
    [[ -d "${member_dir}" ]] || continue

    while IFS= read -r scenario; do
      scenario_dir="${member_dir}/${scenario}"
      [[ -d "${scenario_dir}" ]] || continue

      while IFS= read -r var; do
        var_dir="${scenario_dir}/${var}"
        stage_dir="${var_dir}/${FILE_STAGE}"
        [[ -d "${stage_dir}" ]] || continue

        source_file="$(first_stage_file "${stage_dir}")"
        [[ -n "${source_file}" ]] || continue

        source_data_var="$(pick_data_var "${source_file}" "${var}")"
        if [[ -z "${source_data_var}" ]]; then
          echo "WARN: Could not identify data variable in ${source_file}" >&2
          continue
        fi

        source_units="$(get_attr "${source_file}" "${source_data_var}" "units")"
        source_z_dim="$(pick_zdim "${source_file}" "${source_data_var}")"
        source_z_units=""
        if [[ -n "${source_z_dim}" ]]; then
          source_z_units="$(get_attr "${source_file}" "${source_z_dim}" "units")"
        fi
        IFS=',' read -r source_z_min source_z_max <<< "$(levels_min_max "${source_file}")"
        source_min=""
        source_max=""
        if [[ "${COMPUTE_STATS}" == "yes" ]]; then
          IFS=',' read -r source_min source_max <<< "$(field_min_max "${source_file}" "${source_data_var}")"
        fi

        baseline_target="$(baseline_target_for_var "${var}")"
        baseline_file="$(baseline_file_for_var "${var}" "${baseline_target}")"
        baseline_data_var=""
        baseline_units=""
        baseline_z_dim=""
        baseline_z_units=""
        baseline_z_min=""
        baseline_z_max=""
        baseline_min=""
        baseline_max=""

        if [[ -n "${baseline_file}" && -f "${baseline_file}" ]]; then
          baseline_data_var="$(pick_data_var "${baseline_file}" "${var}")"
          baseline_units="$(get_attr "${baseline_file}" "${baseline_data_var}" "units")"
          baseline_z_dim="$(pick_zdim "${baseline_file}" "${baseline_data_var}")"
          if [[ -n "${baseline_z_dim}" ]]; then
            baseline_z_units="$(get_attr "${baseline_file}" "${baseline_z_dim}" "units")"
          fi
          IFS=',' read -r baseline_z_min baseline_z_max <<< "$(levels_min_max "${baseline_file}")"
          if [[ "${COMPUTE_STATS}" == "yes" ]]; then
            IFS=',' read -r baseline_min baseline_max <<< "$(field_min_max "${baseline_file}" "${baseline_data_var}")"
          fi
        fi

        IFS=',' read -r suggested_z_scale z_note <<< "$(suggest_z_scale_and_note "${source_z_units}" "${source_z_max}")"
        IFS=',' read -r suggested_var_scale var_note <<< "$(
          suggest_var_scale_and_note \
            "${var}" \
            "${source_units}" \
            "${source_min}" \
            "${source_max}" \
            "${baseline_units}" \
            "${baseline_min}" \
            "${baseline_max}"
        )"
        IFS=',' read -r suggested_anomaly_scale suggested_output_bounds add_stage_status add_stage_note <<< "$(
          suggest_add_stage_scale_bounds_and_note \
            "${var}" \
            "${source_units}" \
            "${source_min}" \
            "${source_max}" \
            "${baseline_units}" \
            "${baseline_min}" \
            "${baseline_max}" \
            "${baseline_target}"
        )"
        status="$(status_from_notes "${baseline_target}" "${baseline_file}" "${suggested_z_scale}" "${suggested_var_scale}")"
        notes="${z_note}; ${var_note}; ${add_stage_note}"

        csv_row \
          "${model}" \
          "${member}" \
          "${scenario}" \
          "${var}" \
          "${FILE_STAGE}" \
          "${source_file}" \
          "${source_data_var}" \
          "${source_units}" \
          "${source_z_dim}" \
          "${source_z_units}" \
          "${source_z_min}" \
          "${source_z_max}" \
          "${source_min}" \
          "${source_max}" \
          "${baseline_target}" \
          "${baseline_file}" \
          "${baseline_data_var}" \
          "${baseline_units}" \
          "${baseline_z_dim}" \
          "${baseline_z_units}" \
          "${baseline_z_min}" \
          "${baseline_z_max}" \
          "${baseline_min}" \
          "${baseline_max}" \
          "${suggested_z_scale}" \
          "${suggested_var_scale}" \
          "${suggested_anomaly_scale}" \
          "${suggested_output_bounds}" \
          "${add_stage_status}" \
          "${status}" \
          "${notes}" >> "${OUT_FILE}"

        processed=$((processed + 1))
        if [[ -n "${MAX_GROUPS}" && "${processed}" -ge "${MAX_GROUPS}" ]]; then
          break 4
        fi
      done < <(list_values_or_dirs "${scenario_dir}" "${VAR_FILTER[@]}")
    done < <(list_values_or_dirs "${member_dir}" "${SCENARIO_FILTER[@]}")
  done < <(list_values_or_dirs "${model_dir}" "${MEMBER_FILTER[@]}")
done < <(list_values_or_dirs "${IPCC_ROOT}" "${MODEL_FILTER[@]}")

echo "Wrote unit/depth audit: ${OUT_FILE}"
echo "Representative groups inspected: ${processed}"
