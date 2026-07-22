#!/usr/bin/env bash
# ==============================================================================
#  Audit final downscaled NetCDF products
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Inspect final downscaled products without modifying them
#    - Check expected target family, resolution, grid shape, units, levels
#    - Compute coarse sanity statistics: min, max, and mean
#    - Write a CSV report for cross-scenario/window review
# ==============================================================================

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   DOWNSCALED_ROOT : final downscaled root
#                     (default: /home/SB5/downscaled)
#   MODEL           : model filter
#                     (default: CNRM-ESM2-1)
#   MEMBERS         : optional space-separated member/realization filter
#   SCENARIOS       : optional space-separated scenario filter
#   VARS            : optional space-separated variable filter
#   WINDOWS         : optional space-separated window filter
#   RESOLUTIONS     : optional space-separated resolution filter
#                     (default: 0p05 0p25)
#   GLORYS_ROOT     : GLORYS baseline root
#   HINDCAST_ROOT   : hindcast baseline root on GLORYS coast
#   HINDCAST_0P25_ROOT : hindcast baseline root on native 0p25 grid
#   BASELINE_TAG    : baseline climatology tag
#                     (default: 2006-2014)
#   OUT_FILE        : CSV audit report
#                     (default: data/manifests/downscaled_product_audit.csv)
#   COMPUTE_STATS   : yes | no
#                     (default: yes)
#   MAX_FILES       : optional positive integer limit for quick tests
#   PROGRESS_EVERY  : print progress every N inspected files
#                     (default: 1)
# ==============================================================================

DOWNSCALED_ROOT="${DOWNSCALED_ROOT:-/home/SB5/downscaled}"
MODEL="${MODEL:-CNRM-ESM2-1}"
MEMBERS="${MEMBERS:-}"
SCENARIOS="${SCENARIOS:-}"
VARS="${VARS:-thetao so uo vo zos mlotst siconc chl o2 ph}"
WINDOWS="${WINDOWS:-}"
RESOLUTIONS="${RESOLUTIONS:-0p05 0p25}"
GLORYS_ROOT="${GLORYS_ROOT:-/home/SB5/reanalysis/glorys12v1/monthly_0p05}"
HINDCAST_ROOT="${HINDCAST_ROOT:-/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast}"
HINDCAST_0P25_ROOT="${HINDCAST_0P25_ROOT:-/home/SB5/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25}"
BASELINE_TAG="${BASELINE_TAG:-2006-2014}"
OUT_FILE="${OUT_FILE:-data/manifests/downscaled_product_audit.csv}"
COMPUTE_STATS="${COMPUTE_STATS:-yes}"
MAX_FILES="${MAX_FILES:-}"
PROGRESS_EVERY="${PROGRESS_EVERY:-1}"

GLORYS_BASELINE_VARS="${GLORYS_BASELINE_VARS:-thetao so uo vo zos mlotst siconc}"
HINDCAST_BASELINE_VARS="${HINDCAST_BASELINE_VARS:-chl o2 ph}"

if [[ "${COMPUTE_STATS}" != "yes" && "${COMPUTE_STATS}" != "no" ]]; then
  echo "ERROR: COMPUTE_STATS must be yes or no" >&2
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

for required_cmd in find sort awk sed cdo ncdump; do
  if ! command -v "${required_cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found in PATH: ${required_cmd}" >&2
    exit 1
  fi
done

if [[ ! -d "${DOWNSCALED_ROOT}" ]]; then
  echo "ERROR: DOWNSCALED_ROOT does not exist: ${DOWNSCALED_ROOT}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT_FILE}")"

read -r -a MEMBER_LIST <<< "${MEMBERS}"
read -r -a SCENARIO_LIST <<< "${SCENARIOS}"
read -r -a VAR_LIST <<< "${VARS}"
read -r -a WINDOW_LIST <<< "${WINDOWS}"
read -r -a RESOLUTION_LIST <<< "${RESOLUTIONS}"
read -r -a GLORYS_VAR_LIST <<< "${GLORYS_BASELINE_VARS}"
read -r -a HINDCAST_VAR_LIST <<< "${HINDCAST_BASELINE_VARS}"

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

target_family_for_var() {
  local var="$1"

  if contains_word "${var}" "${GLORYS_VAR_LIST[@]}"; then
    printf 'glorys\n'
  elif contains_word "${var}" "${HINDCAST_VAR_LIST[@]}"; then
    printf 'hindcast\n'
  else
    printf 'none\n'
  fi
}

expected_resolution_for_var() {
  local var="$1"
  local res="$2"
  local family

  family="$(target_family_for_var "${var}")"
  case "${family}:${res}" in
    glorys:0p05|hindcast:0p05|hindcast:0p25)
      printf 'yes\n'
      ;;
    *)
      printf 'no\n'
      ;;
  esac
}

baseline_file_for_product() {
  local var="$1"
  local res="$2"
  local family

  family="$(target_family_for_var "${var}")"
  case "${family}:${res}" in
    glorys:0p05)
      printf '%s/%s/clim_windows/glorys12v1_%s_clim_%s.nc\n' "${GLORYS_ROOT}" "${var}" "${var}" "${BASELINE_TAG}"
      ;;
    hindcast:0p05)
      printf '%s/%s/clim_windows/global_ocean_biogeochemistry_hindcast_%s_clim_%s_grid_0p05_global.nc\n' "${HINDCAST_ROOT}" "${var}" "${var}" "${BASELINE_TAG}"
      ;;
    hindcast:0p25)
      printf '%s/%s/clim_windows/global_ocean_biogeochemistry_hindcast_%s_clim_%s_grid_0p25_global.nc\n' "${HINDCAST_0P25_ROOT}" "${var}" "${var}" "${BASELINE_TAG}"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

fallback_baseline_file_for_product() {
  local var="$1"
  local res="$2"
  local family

  family="$(target_family_for_var "${var}")"
  case "${family}:${res}" in
    hindcast:0p05)
      printf '%s/%s/clim_windows/global_ocean_biogeochemistry_hindcast_%s_clim_%s_grid_0p05_global.nc\n' "${HINDCAST_ROOT}" "${var}" "${var}" "${BASELINE_TAG}"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

get_attr() {
  local file="$1"
  local var="$2"
  local attr="$3"

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
    ' || true
}

grid_summary() {
  local file="$1"

  cdo -s griddes "${file}" 2>/dev/null \
    | awk '
      $1 == "gridtype" {gridtype = $3}
      $1 == "xsize" {xsize = $3}
      $1 == "ysize" {ysize = $3}
      $1 == "xinc" {xinc = $3}
      $1 == "yinc" {yinc = $3}
      END {printf "%s\t%s\t%s\t%s\t%s\n", gridtype, xsize, ysize, xinc, yinc}
    ' || true
}

level_count() {
  local file="$1"

  cdo -s showlevel "${file}" 2>/dev/null \
    | awk '{print NF; exit}' || true
}

stat_values_to_single() {
  local reducer="$1"

  awk -v reducer="${reducer}" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$/) {
          x = $i + 0
          if (n == 0) {
            min = x
            max = x
          }
          if (x < min) min = x
          if (x > max) max = x
          sum += x
          n += 1
        }
      }
    }
    END {
      if (n == 0) {
        print ""
      } else if (reducer == "min") {
        printf "%.12g\n", min
      } else if (reducer == "max") {
        printf "%.12g\n", max
      } else {
        printf "%.12g\n", sum / n
      }
    }
  '
}

cdo_stat() {
  local reducer="$1"
  local file="$2"
  local var="$3"
  local op

  case "${reducer}" in
    min) op="fldmin" ;;
    max) op="fldmax" ;;
    mean) op="fldmean" ;;
    *) return 1 ;;
  esac

  cdo -s output -"${op}" -selname,"${var}" "${file}" 2>/dev/null \
    | stat_values_to_single "${reducer}" || true
}

status_from_checks() {
  local expected_res="$1"
  local grid_ok="$2"
  local baseline_ok="$3"
  local stats_ok="$4"

  if [[ "${expected_res}" != "yes" ]]; then
    printf 'unexpected_resolution\n'
  elif [[ "${baseline_ok}" != "yes" ]]; then
    printf 'missing_baseline_for_comparison\n'
  elif [[ "${grid_ok}" != "yes" ]]; then
    printf 'grid_mismatch\n'
  elif [[ "${stats_ok}" != "yes" ]]; then
    printf 'stats_missing_or_review\n'
  else
    printf 'ok\n'
  fi
}

tmp_files="$(mktemp)"
trap 'rm -f "${tmp_files}"' EXIT

find "${DOWNSCALED_ROOT%/}/${MODEL}" -type f -name '*.nc' 2>/dev/null \
  | sort > "${tmp_files}"

total_candidates="$(wc -l < "${tmp_files}" | awk '{print $1}')"
echo "Downscaled product audit candidates: ${total_candidates}" >&2
echo "Writing audit to: ${OUT_FILE}" >&2

csv_row \
  model member scenario var resolution window target_family file \
  expected_resolution baseline_file baseline_exists \
  gridtype xsize ysize xinc yinc baseline_gridtype baseline_xsize baseline_ysize baseline_xinc baseline_yinc grid_matches_baseline \
  levels units standard_name long_name min max mean status notes \
  > "${OUT_FILE}"

inspected=0
while IFS= read -r file; do
  rel="${file#${DOWNSCALED_ROOT%/}/}"
  IFS='/' read -r model member scenario var resolution window _rest <<< "${rel}"

  [[ "${model}" == "${MODEL}" ]] || continue
  contains_word "${member}" "${MEMBER_LIST[@]}" || continue
  contains_word "${scenario}" "${SCENARIO_LIST[@]}" || continue
  contains_word "${var}" "${VAR_LIST[@]}" || continue
  contains_word "${window}" "${WINDOW_LIST[@]}" || continue
  contains_word "${resolution}" "${RESOLUTION_LIST[@]}" || continue

  inspected=$((inspected + 1))
  if [[ -n "${MAX_FILES}" && "${inspected}" -gt "${MAX_FILES}" ]]; then
    break
  fi

  if (( inspected == 1 || inspected % PROGRESS_EVERY == 0 )); then
    echo "[${inspected}] ${scenario}/${var}/${resolution}/${window}" >&2
  fi

  family="$(target_family_for_var "${var}")"
  expected_res="$(expected_resolution_for_var "${var}" "${resolution}")"
  baseline_file="$(baseline_file_for_product "${var}" "${resolution}")"
  baseline_exists="no"
  if [[ -n "${baseline_file}" && -f "${baseline_file}" ]]; then
    baseline_exists="yes"
  else
    fallback_baseline_file="$(fallback_baseline_file_for_product "${var}" "${resolution}")"
    if [[ -n "${fallback_baseline_file}" && -f "${fallback_baseline_file}" ]]; then
      baseline_file="${fallback_baseline_file}"
      baseline_exists="yes"
    fi
  fi

  IFS=$'\t' read -r gridtype xsize ysize xinc yinc < <(grid_summary "${file}")

  baseline_gridtype=""
  baseline_xsize=""
  baseline_ysize=""
  baseline_xinc=""
  baseline_yinc=""
  grid_matches_baseline="no"

  if [[ "${baseline_exists}" == "yes" ]]; then
    IFS=$'\t' read -r baseline_gridtype baseline_xsize baseline_ysize baseline_xinc baseline_yinc < <(grid_summary "${baseline_file}")
    if [[ "${gridtype}" == "${baseline_gridtype}" \
      && "${xsize}" == "${baseline_xsize}" \
      && "${ysize}" == "${baseline_ysize}" \
      && "${xinc}" == "${baseline_xinc}" \
      && "${yinc}" == "${baseline_yinc}" ]]; then
      grid_matches_baseline="yes"
    fi
  fi

  levels="$(level_count "${file}")"
  units="$(get_attr "${file}" "${var}" units)"
  standard_name="$(get_attr "${file}" "${var}" standard_name)"
  long_name="$(get_attr "${file}" "${var}" long_name)"

  vmin=""
  vmax=""
  vmean=""
  stats_ok="yes"
  notes=""
  if [[ "${COMPUTE_STATS}" == "yes" ]]; then
    vmin="$(cdo_stat min "${file}" "${var}")"
    vmax="$(cdo_stat max "${file}" "${var}")"
    vmean="$(cdo_stat mean "${file}" "${var}")"
    if [[ -z "${vmin}" || -z "${vmax}" || -z "${vmean}" ]]; then
      stats_ok="no"
      notes="one or more CDO stats were empty"
    fi
  else
    stats_ok="yes"
    notes="statistics skipped"
  fi

  status="$(status_from_checks "${expected_res}" "${grid_matches_baseline}" "${baseline_exists}" "${stats_ok}")"

  csv_row \
    "${model}" "${member}" "${scenario}" "${var}" "${resolution}" "${window}" "${family}" "${file}" \
    "${expected_res}" "${baseline_file}" "${baseline_exists}" \
    "${gridtype}" "${xsize}" "${ysize}" "${xinc}" "${yinc}" \
    "${baseline_gridtype}" "${baseline_xsize}" "${baseline_ysize}" "${baseline_xinc}" "${baseline_yinc}" "${grid_matches_baseline}" \
    "${levels}" "${units}" "${standard_name}" "${long_name}" "${vmin}" "${vmax}" "${vmean}" "${status}" "${notes}" \
    >> "${OUT_FILE}"
done < "${tmp_files}"

echo "Wrote downscaled product audit: ${OUT_FILE}"
echo "Files inspected: ${inspected}"
