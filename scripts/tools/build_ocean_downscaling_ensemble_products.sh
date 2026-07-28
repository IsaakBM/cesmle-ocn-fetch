#!/usr/bin/env bash
# ==============================================================================
#  Build model-ensemble ocean downscaling products
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read curated future NetCDF products from /home/SB5/ocean_downscaling_products
#    - Compute ensemble mean and sample standard deviation across model products
#      with CDO ensmean and ensstd1
#    - Write outputs back into the same curated future tree grammar:
#        future/ensemble/model_mean/<scenario>/<var>/<window>/<resolution>/
#        future/ensemble/model_sd/<scenario>/<var>/<window>/<resolution>/
#    - Exclude legacy CESM/RCP-era products by default
# ==============================================================================

set -euo pipefail
shopt -s nullglob

PRODUCT_ROOT="${PRODUCT_ROOT:-/home/SB5/ocean_downscaling_products}"
FUTURE_ROOT="${FUTURE_ROOT:-${PRODUCT_ROOT}/future}"
SCENARIO="${SCENARIO:-}"
VAR="${VAR:-}"
WINDOW="${WINDOW:-}"
RESOLUTION="${RESOLUTION:-}"
MODELS="${MODELS:-auto}"
EXCLUDE_MODELS="${EXCLUDE_MODELS:-cesm_f09_g16 legacy_downscaled_rcp85 ensemble}"
MIN_MODELS="${MIN_MODELS:-2}"
OVERWRITE="${OVERWRITE:-no}"
FILE_INCLUDE_REGEX="${FILE_INCLUDE_REGEX:-}"
VALIDATE_INPUT_TIME="${VALIDATE_INPUT_TIME:-warn}"

if [[ -z "${SCENARIO}" || -z "${VAR}" || -z "${WINDOW}" || -z "${RESOLUTION}" ]]; then
  echo "ERROR: SCENARIO, VAR, WINDOW, and RESOLUTION must be set" >&2
  exit 1
fi

if [[ ! -d "${FUTURE_ROOT}" ]]; then
  echo "ERROR: FUTURE_ROOT does not exist: ${FUTURE_ROOT}" >&2
  exit 1
fi

if [[ "${OVERWRITE}" != "yes" && "${OVERWRITE}" != "no" ]]; then
  echo "ERROR: OVERWRITE must be yes or no" >&2
  exit 1
fi

if [[ "${VALIDATE_INPUT_TIME}" != "off" && "${VALIDATE_INPUT_TIME}" != "warn" && "${VALIDATE_INPUT_TIME}" != "fail" ]]; then
  echo "ERROR: VALIDATE_INPUT_TIME must be off, warn, or fail" >&2
  exit 1
fi

if ! [[ "${MIN_MODELS}" =~ ^[0-9]+$ ]] || [[ "${MIN_MODELS}" -eq 0 ]]; then
  echo "ERROR: MIN_MODELS must be a positive integer" >&2
  exit 1
fi

if ! command -v cdo >/dev/null 2>&1; then
  echo "ERROR: Required command not found in PATH: cdo" >&2
  exit 1
fi

contains_word() {
  local needle="$1"
  shift
  local candidate

  for candidate in "$@"; do
    [[ "${candidate}" == "${needle}" ]] && return 0
  done
  return 1
}

read -r -a MODEL_LIST <<< "${MODELS}"
read -r -a EXCLUDE_MODEL_LIST <<< "${EXCLUDE_MODELS}"

declare -a INPUT_FILES=()
declare -a SOURCE_LABELS=()
declare -a SOURCE_PATHS=()

while IFS= read -r model_dir; do
  model="$(basename "${model_dir}")"

  contains_word "${model}" "${EXCLUDE_MODEL_LIST[@]}" && continue
  if [[ "${MODELS}" != "auto" ]] && ! contains_word "${model}" "${MODEL_LIST[@]}"; then
    continue
  fi

  while IFS= read -r realization_dir; do
    realization="$(basename "${realization_dir}")"
    product_dir="${realization_dir}/${SCENARIO}/${VAR}/${WINDOW}/${RESOLUTION}"
    [[ -d "${product_dir}" ]] || continue

    declare -a matches=()
    if [[ -n "${FILE_INCLUDE_REGEX}" ]]; then
      while IFS= read -r match; do
        matches+=("${match}")
      done < <(
        find "${product_dir}" -maxdepth 1 -type f -name '*.nc' \
          | sed "s#^${PRODUCT_ROOT}/##" \
          | grep -E "${FILE_INCLUDE_REGEX}" \
          | sed "s#^#${PRODUCT_ROOT}/#" \
          | sort
      )
    else
      while IFS= read -r match; do
        matches+=("${match}")
      done < <(find "${product_dir}" -maxdepth 1 -type f -name '*.nc' | sort)
    fi

    if (( ${#matches[@]} == 0 )); then
      continue
    fi
    if (( ${#matches[@]} > 1 )); then
      echo "ERROR: Multiple NetCDF files found for one model product; set FILE_INCLUDE_REGEX to disambiguate: ${product_dir}" >&2
      printf '  %s\n' "${matches[@]}" >&2
      exit 1
    fi

    INPUT_FILES+=("${matches[0]}")
    SOURCE_LABELS+=("${model}:${realization}")
    SOURCE_PATHS+=("${matches[0]}")
  done < <(find "${model_dir}" -mindepth 1 -maxdepth 1 -type d | sort)
done < <(find "${FUTURE_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort)

if (( ${#INPUT_FILES[@]} < MIN_MODELS )); then
  echo "ERROR: Need at least ${MIN_MODELS} model products for ensemble, found ${#INPUT_FILES[@]} for SCENARIO=${SCENARIO} VAR=${VAR} WINDOW=${WINDOW} RESOLUTION=${RESOLUTION}" >&2
  exit 1
fi

if [[ "${VALIDATE_INPUT_TIME}" != "off" ]]; then
  python3 - <<PY
import re
import sys
import numpy as np
import xarray as xr

window = "${WINDOW}"
mode = "${VALIDATE_INPUT_TIME}"
input_files = """${SOURCE_PATHS[*]}""".split()
start_year, end_year = [int(x) for x in window.split("-", 1)]

def years_from_values(values):
    years = []
    for value in np.ravel(values):
        text = str(value)
        match = re.match(r"^([0-9]{4})", text)
        if match:
            years.append(int(match.group(1)))
    return years

issues = []
for path in input_files:
    with xr.open_dataset(path) as ds:
        if "time" not in ds:
            issues.append(f"{path}: missing time coordinate")
            continue
        years = years_from_values(ds["time"].values)
        if years and not all(start_year <= year <= end_year for year in years):
            issues.append(f"{path}: time years {min(years)}-{max(years)} outside {window}")
        if "time_bnds" in ds:
            bnd_years = years_from_values(ds["time_bnds"].values)
            if bnd_years and (min(bnd_years) != start_year or max(bnd_years) != end_year):
                issues.append(f"{path}: time_bnds years {min(bnd_years)}-{max(bnd_years)} do not match {window}")

if issues:
    for issue in issues:
        print(f"[TIME-WARN] {issue}", file=sys.stderr)
    if mode == "fail":
        raise SystemExit(2)
PY
fi

mean_dir="${FUTURE_ROOT}/ensemble/model_mean/${SCENARIO}/${VAR}/${WINDOW}/${RESOLUTION}"
sd_dir="${FUTURE_ROOT}/ensemble/model_sd/${SCENARIO}/${VAR}/${WINDOW}/${RESOLUTION}"
mean_out="${mean_dir}/ocean_downscaling_ensemble_model_mean_${VAR}_${SCENARIO}_${WINDOW}_${RESOLUTION}.nc"
sd_out="${sd_dir}/ocean_downscaling_ensemble_model_sd_${VAR}_${SCENARIO}_${WINDOW}_${RESOLUTION}.nc"

mkdir -p "${mean_dir}" "${sd_dir}"

if [[ "${OVERWRITE}" != "yes" ]]; then
  if [[ -f "${mean_out}" && -f "${sd_out}" ]]; then
    echo "[SKIP] Ensemble outputs exist (OVERWRITE=no): ${mean_out} and ${sd_out}"
    exit 0
  fi
  if [[ -f "${mean_out}" || -f "${sd_out}" ]]; then
    echo "ERROR: Partial ensemble outputs already exist with OVERWRITE=no; rerun with OVERWRITE=yes to refresh" >&2
    echo "  mean: ${mean_out}" >&2
    echo "  sd  : ${sd_out}" >&2
    exit 1
  fi
fi

if [[ "${OVERWRITE}" == "yes" ]]; then
  rm -f "${mean_out}" "${sd_out}"
fi

echo "[START] SCENARIO=${SCENARIO} VAR=${VAR} WINDOW=${WINDOW} RESOLUTION=${RESOLUTION}"
echo "[INFO ] Ensemble members (${#INPUT_FILES[@]}): ${SOURCE_LABELS[*]}"

cdo -O ensmean "${INPUT_FILES[@]}" "${mean_out}"
cdo -O ensstd1 "${INPUT_FILES[@]}" "${sd_out}"

python3 - <<PY
import numpy as np
import xarray as xr

window = "${WINDOW}"
outputs = ["${mean_out}", "${sd_out}"]

try:
    start_year, end_year = window.split("-", 1)
except ValueError as exc:
    raise ValueError(f"WINDOW must look like YYYY-YYYY, got {window!r}") from exc

start_text = f"{start_year}-01-01"
end_text = f"{end_year}-12-31"
start = np.datetime64(start_text)
end = np.datetime64(end_text)
midpoint = start + (end - start) // 2

for path in outputs:
    with xr.open_dataset(path) as ds:
        out = ds.load()
    if "time" in out.dims:
        if out.sizes["time"] != 1:
            raise ValueError(
                f"Cannot stamp climatology time on ensemble output with time size "
                f"{out.sizes['time']}: {path}"
            )
        out = out.assign_coords(time=("time", np.array([midpoint], dtype="datetime64[ns]")))
    else:
        out = out.expand_dims(time=np.array([midpoint], dtype="datetime64[ns]"))
    attrs = dict(out["time"].attrs)
    attrs.update({"long_name": "climatology time", "climatology": "time_bnds"})
    out["time"].attrs = attrs
    out["time_bnds"] = xr.DataArray(
        np.array([[start, end]], dtype="datetime64[ns]"),
        coords={"time": out["time"], "bnds": [0, 1]},
        dims=("time", "bnds"),
    )
    out.attrs["climatology_window_start"] = start_text
    out.attrs["climatology_window_end"] = end_text
    out.attrs["climatology_time_policy"] = (
        "time coordinate set to midpoint of ensemble climatology window; "
        "time_bnds stores the configured window bounds"
    )
    out.to_netcdf(path, format="NETCDF4")
PY

if command -v ncatted >/dev/null 2>&1; then
  members_text="${SOURCE_LABELS[*]}"
  source_files_text="${SOURCE_PATHS[*]}"
  excluded_text="${EXCLUDE_MODEL_LIST[*]}"

  ncatted -O \
    -a title,global,o,c,"Ocean downscaling model ensemble product" \
    -a product_statistic,global,o,c,"model_mean" \
    -a ensemble_axis,global,o,c,"model" \
    -a ensemble_scenario,global,o,c,"${SCENARIO}" \
    -a ensemble_variable,global,o,c,"${VAR}" \
    -a ensemble_window,global,o,c,"${WINDOW}" \
    -a ensemble_resolution,global,o,c,"${RESOLUTION}" \
    -a n_ensemble_members,global,o,c,"${#INPUT_FILES[@]}" \
    -a ensemble_members,global,o,c,"${members_text}" \
    -a excluded_models,global,o,c,"${excluded_text}" \
    -a source_product_root,global,o,c,"${PRODUCT_ROOT}" \
    -a source_files,global,o,c,"${source_files_text}" \
    -a description,global,o,c,"Mean across available model products for this scenario, variable, window, and resolution." \
    "${mean_out}"

  ncatted -O \
    -a title,global,o,c,"Ocean downscaling model ensemble product" \
    -a product_statistic,global,o,c,"model_standard_deviation" \
    -a standard_deviation_method,global,o,c,"CDO ensstd1; sample standard deviation normalized by n-1" \
    -a ensemble_axis,global,o,c,"model" \
    -a ensemble_scenario,global,o,c,"${SCENARIO}" \
    -a ensemble_variable,global,o,c,"${VAR}" \
    -a ensemble_window,global,o,c,"${WINDOW}" \
    -a ensemble_resolution,global,o,c,"${RESOLUTION}" \
    -a n_ensemble_members,global,o,c,"${#INPUT_FILES[@]}" \
    -a ensemble_members,global,o,c,"${members_text}" \
    -a excluded_models,global,o,c,"${excluded_text}" \
    -a source_product_root,global,o,c,"${PRODUCT_ROOT}" \
    -a source_files,global,o,c,"${source_files_text}" \
    -a description,global,o,c,"Sample standard deviation across available model products for this scenario, variable, window, and resolution." \
    "${sd_out}"
else
  echo "[WARN] ncatted not found; skipping ensemble metadata annotation" >&2
fi

echo "[WRITE] mean=${mean_out}"
echo "[WRITE] sd=${sd_out}"
