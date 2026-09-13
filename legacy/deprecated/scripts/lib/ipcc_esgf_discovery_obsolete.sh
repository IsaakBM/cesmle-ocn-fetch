#!/usr/bin/env bash
# Historical helpers removed from the active library on 2026-09-12.
# No repository callers remained. Source explicitly only for reproduction.

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

ipcc_esgf_label() {
  local model="$1"
  local scenario="$2"
  local member="$3"

  printf 'ipcc_esgf_%s_%s_%s\n' "$model" "$scenario" "$member"
}
