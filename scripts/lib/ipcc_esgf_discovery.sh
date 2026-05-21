#!/usr/bin/env bash
# ==============================================================================
#  Shared IPCC/ESGF discovery helpers
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
# ==============================================================================

# This file is meant to be sourced by runner scripts.

ipcc_esgf_parse_filename() {
  local path="$1"
  local base name

  base="$(basename "$path")"
  name="${base%.nc}"

  # Handle files that already include processing suffixes after .nc-like stems.
  # Expected CMIP/ESGF stem:
  #   <var>_<table>_<model>_<scenario>_<member>_<grid>_<timerange>[...]
  IFS='_' read -r IPCC_VAR IPCC_TABLE_ID IPCC_MODEL IPCC_SCENARIO IPCC_MEMBER IPCC_GRID IPCC_TIMERANGE _ <<< "$name"

  if [[ -z "${IPCC_VAR:-}" || -z "${IPCC_TABLE_ID:-}" || -z "${IPCC_MODEL:-}" ||
        -z "${IPCC_SCENARIO:-}" || -z "${IPCC_MEMBER:-}" || -z "${IPCC_GRID:-}" ]]; then
    return 1
  fi

  [[ "${IPCC_MEMBER}" =~ ^r[0-9]+i[0-9]+p[0-9]+f[0-9]+$ ]] || return 1
  [[ "${IPCC_SCENARIO}" == historical || "${IPCC_SCENARIO}" == ssp[0-9][0-9][0-9] ]] || return 1

  return 0
}

ipcc_esgf_discover_download_groups() {
  local root="$1"
  local pattern="${2:-*.nc}"
  local file

  [[ -d "$root" ]] || return 0

  while IFS= read -r file; do
    if ipcc_esgf_parse_filename "$file"; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$IPCC_MODEL" "$IPCC_SCENARIO" "$IPCC_VAR" "$IPCC_MEMBER" "$IPCC_TABLE_ID" "$IPCC_GRID"
    fi
  done < <(find "$root" -type f -name "$pattern" | sort)
}

ipcc_esgf_discover_monthly_groups() {
  local root="$1"
  local subdir="${2:-parts}"
  local model scenario var

  [[ -d "$root" ]] || return 0

  while IFS= read -r model_dir; do
    model="$(basename "$model_dir")"
    while IFS= read -r scenario_dir; do
      scenario="$(basename "$scenario_dir")"
      [[ "$scenario" == historical || "$scenario" == ssp[0-9][0-9][0-9] ]] || continue
      while IFS= read -r var_dir; do
        var="$(basename "$var_dir")"
        [[ -d "${var_dir}/${subdir}" ]] || continue
        printf '%s\t%s\t%s\n' "$model" "$scenario" "$var"
      done < <(find "$scenario_dir" -mindepth 1 -maxdepth 1 -type d | sort)
    done < <(find "$model_dir" -mindepth 1 -maxdepth 1 -type d | sort)
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
}

ipcc_esgf_members_from_files() {
  local dir="$1"
  local glob="${2:-*.nc}"
  local file

  [[ -d "$dir" ]] || return 0

  while IFS= read -r file; do
    if ipcc_esgf_parse_filename "$file"; then
      printf '%s\n' "$IPCC_MEMBER"
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name "$glob" | sort)
}

ipcc_esgf_members_from_product_files() {
  local dir="$1"
  local model="$2"
  local scenario="$3"
  local var="$4"
  local glob="${5:-*.nc}"
  local file base remainder member

  [[ -d "$dir" ]] || return 0

  while IFS= read -r file; do
    base="$(basename "$file")"
    remainder="${base#ipcc_esgf_${model}_${scenario}_}"
    [[ "$remainder" != "$base" ]] || continue
    member="${remainder%%_${var}_*}"
    [[ "$member" != "$remainder" ]] || continue
    [[ "$member" =~ ^r[0-9]+i[0-9]+p[0-9]+f[0-9]+$ ]] || continue
    printf '%s\n' "$member"
  done < <(find "$dir" -maxdepth 1 -type f -name "$glob" | sort)
}

ipcc_esgf_resolve_member() {
  local dir="$1"
  local glob="${2:-*.nc}"
  local requested="${MEMBER:-auto}"
  local members=()
  local member

  mapfile -t members < <(ipcc_esgf_members_from_files "$dir" "$glob" | sort -u)

  if [[ "$requested" != "auto" ]]; then
    for member in "${members[@]}"; do
      if [[ "$member" == "$requested" ]]; then
        printf '%s\n' "$requested"
        return 0
      fi
    done
    echo "ERROR: MEMBER=${requested} not found in ${dir} for glob ${glob}" >&2
    return 1
  fi

  case "${#members[@]}" in
    0)
      echo "WARN: No ESGF members found in ${dir} for glob ${glob}" >&2
      return 2
      ;;
    1)
      printf '%s\n' "${members[0]}"
      return 0
      ;;
    *)
      echo "ERROR: Multiple ESGF members found in ${dir} for glob ${glob}: ${members[*]}" >&2
      echo "       Set MEMBER=<member>, for example MEMBER=${members[0]}" >&2
      return 1
      ;;
  esac
}

ipcc_esgf_resolve_product_member() {
  local dir="$1"
  local model="$2"
  local scenario="$3"
  local var="$4"
  local glob="${5:-*.nc}"
  local requested="${MEMBER:-auto}"
  local members=()
  local member

  mapfile -t members < <(ipcc_esgf_members_from_product_files "$dir" "$model" "$scenario" "$var" "$glob" | sort -u)

  if [[ "$requested" != "auto" ]]; then
    for member in "${members[@]}"; do
      if [[ "$member" == "$requested" ]]; then
        printf '%s\n' "$requested"
        return 0
      fi
    done
    echo "ERROR: MEMBER=${requested} not found in ${dir} for ${model} ${scenario} ${var}" >&2
    return 1
  fi

  case "${#members[@]}" in
    0)
      echo "WARN: No ESGF members found in ${dir} for ${model} ${scenario} ${var}" >&2
      return 2
      ;;
    1)
      printf '%s\n' "${members[0]}"
      return 0
      ;;
    *)
      echo "ERROR: Multiple ESGF members found in ${dir} for ${model} ${scenario} ${var}: ${members[*]}" >&2
      echo "       Set MEMBER=<member>, for example MEMBER=${members[0]}" >&2
      return 1
      ;;
  esac
}

ipcc_esgf_label() {
  local model="$1"
  local scenario="$2"
  local member="$3"

  printf 'ipcc_esgf_%s_%s_%s\n' "$model" "$scenario" "$member"
}
