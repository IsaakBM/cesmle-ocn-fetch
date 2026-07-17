#!/usr/bin/env bash
# ==============================================================================
#  Stage ocean downscaling sample products for the Shiny viewer
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Copy a small Shiny-viewer-ready sample product tree from curated
#      layer, pelagic, and individual-depth product outputs
#    - Preserve the viewer product layout:
#        layers/baseline/<variable>/<resolution>/*
#        layers/future/<scenario>/<variable>/<window>/<resolution>/*
#        pelagic/baseline/<variable>/<resolution>/*
#        pelagic/future/<scenario>/<variable>/<window>/<resolution>/*
#        depths/baseline/<variable>/<resolution>/*
#        depths/future/<scenario>/<variable>/<window>/<resolution>/*
#    - Restrict sample staging to one resolution, usually 0p05
#    - For future products with multiple realizations/members, keep one
#      deterministic realization per model/scenario/variable/window/resolution
#    - Write staged GeoTIFF manifests that match only copied/planned files
#
#  Intended to be run on Slurm-based HPC systems or an HPC login node.
# ==============================================================================

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   LAYERS_SOURCE_ROOT  : fine-layer product source root
#                         (default: /home/SB5/ocean_downscaling_products_layers_geotiff)
#   PELAGIC_SOURCE_ROOT : pelagic product source root
#                         (default: /home/SB5/ocean_downscaling_products_pelagic_geotiff)
#   DEPTHS_SOURCE_ROOT  : individual-depth product source root
#                         (default: /home/SB5/ocean_downscaling_products_depths_geotiff)
#   STAGE_ROOT          : output root that will contain layers/, pelagic/, and depths/
#                         (default: /home/SB5/ocean_downscaling_sample_products_geotiff)
#   RESOLUTION          : resolution directory to copy
#                         (default: 0p05)
#   MEMBER              : retained for compatibility with older runners
#                         (default: 001)
#   PHYSICAL_VARS       : retained for compatibility with older runners
#                         (default: thetao so uo)
#   EXTENSIONS          : space-separated filename extensions to copy
#                         (default: tif tiff)
#   DRY_RUN             : yes | no
#                         yes -> print planned copies without writing files
#                         no  -> copy files
#                         (default: no)
#   OVERWRITE           : yes | no
#                         yes -> replace existing staged files
#                         no  -> keep existing staged files
#                         (default: yes)
#   STAGE_MANIFESTS     : yes | no
#                         yes -> create filtered staged manifest CSVs
#                         no  -> skip manifest staging
#                         (default: yes)
#   STAGE_DEPTHS        : yes | no
#                         yes -> include individual-depth GeoTIFF products
#                         no  -> stage only layers and pelagic products
#                         (default: yes)
# ==============================================================================

LAYERS_SOURCE_ROOT="${LAYERS_SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_layers_geotiff}"
PELAGIC_SOURCE_ROOT="${PELAGIC_SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_pelagic_geotiff}"
DEPTHS_SOURCE_ROOT="${DEPTHS_SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_depths_geotiff}"
STAGE_ROOT="${STAGE_ROOT:-/home/SB5/ocean_downscaling_sample_products_geotiff}"
RESOLUTION="${RESOLUTION:-0p05}"
MEMBER="${MEMBER:-001}"
PHYSICAL_VARS="${PHYSICAL_VARS:-thetao so uo}"
EXTENSIONS="${EXTENSIONS:-tif tiff}"
DRY_RUN="${DRY_RUN:-no}"
OVERWRITE="${OVERWRITE:-yes}"
STAGE_MANIFESTS="${STAGE_MANIFESTS:-yes}"
STAGE_DEPTHS="${STAGE_DEPTHS:-yes}"

case "${DRY_RUN}" in
  yes|no) ;;
  *)
    echo "ERROR: DRY_RUN must be yes or no"
    exit 1
    ;;
esac

case "${OVERWRITE}" in
  yes|no) ;;
  *)
    echo "ERROR: OVERWRITE must be yes or no"
    exit 1
    ;;
esac

case "${STAGE_MANIFESTS}" in
  yes|no) ;;
  *)
    echo "ERROR: STAGE_MANIFESTS must be yes or no"
    exit 1
    ;;
esac

case "${STAGE_DEPTHS}" in
  yes|no) ;;
  *)
    echo "ERROR: STAGE_DEPTHS must be yes or no"
    exit 1
    ;;
esac

SELECTED_REALIZATIONS=""

keep_future_realization() {
  local product_type="$1"
  local model="$2"
  local realization="$3"
  local scenario="$4"
  local variable="$5"
  local window="$6"
  local resolution="$7"
  local key selected entry_key entry_value

  key="${product_type}|${model}|${scenario}|${variable}|${window}|${resolution}"
  selected=""
  while IFS='=' read -r entry_key entry_value; do
    if [[ "${entry_key}" == "${key}" ]]; then
      selected="${entry_value}"
      break
    fi
  done <<<"${SELECTED_REALIZATIONS}"

  if [[ -z "${selected}" ]]; then
    SELECTED_REALIZATIONS="${SELECTED_REALIZATIONS}${key}=${realization}"$'\n'
    echo "[INFO] ${product_type}/future/${model}/${scenario}/${variable}/${window}/${resolution}: selected realization ${realization}"
    return 0
  fi

  [[ "${realization}" == "${selected}" ]]
}

copy_or_report() {
  local src="$1"
  local dest="$2"

  if [[ "${DRY_RUN}" == "yes" ]]; then
    echo "[DRY-RUN] ${src} -> ${dest}"
    return 0
  fi

  mkdir -p "$(dirname "${dest}")"

  if [[ -f "${dest}" && "${OVERWRITE}" == "no" ]]; then
    echo "[SKIP] Existing staged file: ${dest}"
    return 1
  fi

  cp -p "${src}" "${dest}"
  echo "[COPY] ${src} -> ${dest}"
  return 0
}

stage_one_file() {
  local product_type="$1"
  local src_root="$2"
  local src="$3"
  local rel_path family model realization scenario variable window resolution file_name dest
  local -a path_parts

  rel_path="${src#${src_root}/}"
  file_name="$(basename "${src}")"

  IFS='/' read -r -a path_parts <<<"${rel_path}"
  family="${path_parts[0]:-}"

  if [[ "${family}" == "baseline" ]]; then
    variable="${path_parts[1]:-}"
    resolution="${path_parts[2]:-}"
    if [[ "${resolution}" != "${RESOLUTION}" ]]; then
      return 0
    fi
    dest="${STAGE_ROOT}/${product_type}/baseline/${variable}/${resolution}/${file_name}"
  elif [[ "${family}" == "future" ]]; then
    if (( ${#path_parts[@]} >= 7 )); then
      model="${path_parts[1]:-}"
      realization="${path_parts[2]:-}"
      scenario="${path_parts[3]:-}"
      variable="${path_parts[4]:-}"
      window="${path_parts[5]:-}"
      resolution="${path_parts[6]:-}"
    else
      # Legacy fallback for the old Shiny-facing tree:
      # future/<variable>/<window>/<resolution>/<file>.
      model="legacy"
      realization="legacy"
      scenario="legacy"
      variable="${path_parts[1]:-}"
      window="${path_parts[2]:-}"
      resolution="${path_parts[3]:-}"
    fi

    if [[ "${resolution}" != "${RESOLUTION}" ]]; then
      return 0
    fi

    if ! keep_future_realization "${product_type}" "${model}" "${realization}" "${scenario}" "${variable}" "${window}" "${resolution}"; then
      echo "[SKIP] ${product_type}/${rel_path} (keeping selected realization only)"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      return 0
    fi

    dest="${STAGE_ROOT}/${product_type}/future/${scenario}/${variable}/${window}/${resolution}/${file_name}"
  else
    echo "[WARN] Skipping file outside baseline/future layout: ${rel_path}" >&2
    return 0
  fi

  if copy_or_report "${src}" "${dest}"; then
    COPIED_COUNT=$((COPIED_COUNT + 1))
  else
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  fi
}

stage_product_type() {
  local product_type="$1"
  local src_root="$2"
  local extension file

  if [[ ! -d "${src_root}" ]]; then
    echo "[WARN] Missing ${product_type} source root: ${src_root}" >&2
    return 0
  fi

  echo
  echo "[STEP] Staging ${product_type} products from: ${src_root}"

  for extension in ${EXTENSIONS}; do
    while IFS= read -r -d '' file; do
      stage_one_file "${product_type}" "${src_root}" "${file}"
    done < <(
      find "${src_root}/baseline" "${src_root}/future" \
        -type f \
        -path "*/${RESOLUTION}/*.${extension}" \
        -print0 2>/dev/null \
        | sort -z
    )
  done
}

stage_manifests() {
  if [[ "${STAGE_MANIFESTS}" != "yes" ]]; then
    return 0
  fi

  echo
  echo "[STEP] Staging filtered GeoTIFF manifests"

  if [[ "${DRY_RUN}" == "yes" ]]; then
    echo "[DRY-RUN] Would write filtered manifests under: ${STAGE_ROOT}/manifests"
  else
    mkdir -p "${STAGE_ROOT}/manifests"
  fi

  python3 - \
    "${LAYERS_SOURCE_ROOT}" \
    "${PELAGIC_SOURCE_ROOT}" \
    "${DEPTHS_SOURCE_ROOT}" \
    "${STAGE_ROOT}" \
    "${RESOLUTION}" \
    "${MEMBER}" \
    "${PHYSICAL_VARS}" \
    "${DRY_RUN}" \
    "${STAGE_DEPTHS}" <<'PY'
import csv
import os
import sys

try:
    import rasterio
except ImportError:
    rasterio = None

(
    layers_source_root,
    pelagic_source_root,
    depths_source_root,
    stage_root,
    resolution,
    _member,
    _physical_vars_text,
    dry_run,
    stage_depths,
) = sys.argv[1:10]

selected_realizations = {}


def geotiff_tags(path):
    if rasterio is None or not os.path.isfile(path):
        return {}

    try:
        with rasterio.open(path) as src:
            return src.tags()
    except Exception as exc:
        print(f"[WARN] Could not read GeoTIFF tags for {path}: {exc}", file=sys.stderr)
        return {}


def backfill_manifest_metadata(row):
    missing_fields = [
        field for field in ("units", "scale_factor", "offset", "decode_formula")
        if not str(row.get(field, "")).strip()
    ]
    if not missing_fields:
        return

    geotiff_file = row.get("geotiff_file", "")
    tags = geotiff_tags(geotiff_file)
    if not tags:
        return

    for field in missing_fields:
        if field in tags and str(tags[field]).strip():
            row[field] = tags[field]


def iter_manifest_rows(product_type, source_root):
    if not os.path.isdir(source_root):
        return

    manifest = os.path.join(source_root, "geotiff_manifest.csv")
    if not os.path.isfile(manifest):
        print(f"[WARN] Missing root GeoTIFF manifest for {product_type}: {manifest}", file=sys.stderr)
        return

    with open(manifest, newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            row["_manifest_file"] = manifest
            row["_product_type"] = product_type
            yield row


def staged_info_for_row(row, source_root):
    geotiff_file = row.get("geotiff_file", "")
    if not geotiff_file:
        return None

    abs_file = os.path.abspath(geotiff_file)
    abs_root = os.path.abspath(source_root)
    try:
        rel_path = os.path.relpath(abs_file, abs_root)
    except ValueError:
        return None

    if rel_path.startswith(".."):
        return None

    parts = rel_path.split(os.sep)
    if len(parts) < 4:
        return None

    family = parts[0]
    file_name = os.path.basename(abs_file)
    product_type = row["_product_type"]
    info = {
        "family": family,
        "model": "baseline" if family == "baseline" else "",
        "realization": "baseline" if family == "baseline" else "",
        "scenario": "baseline" if family == "baseline" else "",
        "variable": "",
        "window": "2006-2014" if family == "baseline" else "",
        "resolution": "",
        "source_relative_path": rel_path,
    }

    if family == "baseline":
        variable = parts[1]
        source_resolution = parts[2]
        if source_resolution != resolution:
            return None
        info["variable"] = variable
        info["resolution"] = source_resolution
        staged_rel = os.path.join(product_type, "baseline", variable, resolution, file_name)
    elif family == "future":
        if len(parts) >= 7:
            model = parts[1]
            realization = parts[2]
            scenario = parts[3]
            variable = parts[4]
            window = parts[5]
            source_resolution = parts[6]
        else:
            # Legacy fallback for future/<variable>/<window>/<resolution>/<file>.
            model = "legacy"
            realization = "legacy"
            scenario = "legacy"
            variable = parts[1]
            window = parts[2]
            source_resolution = parts[3] if len(parts) >= 4 else resolution

        if source_resolution != resolution:
            return None

        key = (product_type, model, scenario, variable, window, source_resolution)
        selected = selected_realizations.get(key)
        if selected is None:
            selected_realizations[key] = realization
        elif realization != selected:
            return None

        info.update(
            {
                "model": model,
                "realization": realization,
                "scenario": scenario,
                "variable": variable,
                "window": window,
                "resolution": source_resolution,
            }
        )
        staged_rel = os.path.join(product_type, "future", scenario, variable, window, resolution, file_name)
    else:
        return None

    info["staged_relative_path"] = staged_rel
    return info


def write_manifest(name, rows):
    if not rows:
        print(f"[WARN] No manifest rows staged for: {name}", file=sys.stderr)
        return

    base_fields = []
    for row in rows:
        for field in row.keys():
            if field.startswith("_") or field in base_fields:
                continue
            base_fields.append(field)
    extra_fields = [
        "product_type",
        "manifest_file",
        "family",
        "model",
        "realization",
        "scenario",
        "variable",
        "window",
        "resolution",
        "source_relative_path",
        "staged_file",
        "staged_relative_path",
    ]
    fieldnames = base_fields + [field for field in extra_fields if field not in base_fields]
    out_path = os.path.join(stage_root, "manifests", name)

    if dry_run == "yes":
        print(f"[DRY-RUN] {out_path} rows={len(rows)}")
        return

    with open(out_path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"[MANIFEST] {out_path} rows={len(rows)}")


all_rows = []
by_product = {}
product_roots = [
    ("layers", layers_source_root),
    ("pelagic", pelagic_source_root),
]
if stage_depths == "yes":
    product_roots.append(("depths", depths_source_root))

for product_type, source_root in product_roots:
    rows = []
    for row in sorted(iter_manifest_rows(product_type, source_root) or [], key=lambda item: item.get("geotiff_file", "")):
        staged_info = staged_info_for_row(row, source_root)
        if staged_info is None:
            continue
        clean = {key: value for key, value in row.items() if not key.startswith("_")}
        clean["product_type"] = product_type
        clean["manifest_file"] = row["_manifest_file"]
        clean.update(staged_info)
        clean["staged_file"] = os.path.abspath(os.path.join(stage_root, staged_info["staged_relative_path"]))
        backfill_manifest_metadata(clean)
        rows.append(clean)

    by_product[product_type] = rows
    all_rows.extend(rows)

write_manifest("layers_geotiff_manifest.csv", by_product.get("layers", []))
write_manifest("pelagic_geotiff_manifest.csv", by_product.get("pelagic", []))
if stage_depths == "yes":
    write_manifest("depths_geotiff_manifest.csv", by_product.get("depths", []))
write_manifest("geotiff_manifest.csv", all_rows)
PY
}

echo "============================================================"
echo "Staging ocean downscaling sample products"
echo "LAYERS SOURCE  : ${LAYERS_SOURCE_ROOT}"
echo "PELAGIC SOURCE : ${PELAGIC_SOURCE_ROOT}"
echo "DEPTHS SOURCE  : ${DEPTHS_SOURCE_ROOT}"
echo "STAGE ROOT     : ${STAGE_ROOT}"
echo "RESOLUTION     : ${RESOLUTION}"
echo "REALIZATION    : first sorted per model/scenario/variable/window"
echo "EXTENSIONS     : ${EXTENSIONS}"
echo "DRY RUN        : ${DRY_RUN}"
echo "OVERWRITE      : ${OVERWRITE}"
echo "STAGE MANIFESTS: ${STAGE_MANIFESTS}"
echo "STAGE DEPTHS   : ${STAGE_DEPTHS}"
echo "============================================================"

if [[ "${DRY_RUN}" == "no" ]]; then
  mkdir -p "${STAGE_ROOT}/layers" "${STAGE_ROOT}/pelagic"
  if [[ "${STAGE_DEPTHS}" == "yes" ]]; then
    mkdir -p "${STAGE_ROOT}/depths"
  fi
fi

COPIED_COUNT=0
SKIPPED_COUNT=0
stage_product_type "layers" "${LAYERS_SOURCE_ROOT}"
stage_product_type "pelagic" "${PELAGIC_SOURCE_ROOT}"
if [[ "${STAGE_DEPTHS}" == "yes" ]]; then
  stage_product_type "depths" "${DEPTHS_SOURCE_ROOT}"
fi
stage_manifests

echo
if [[ "${DRY_RUN}" == "yes" ]]; then
  echo "Dry run complete. Planned staged files: ${COPIED_COUNT}"
else
  echo "Done. Staged files copied: ${COPIED_COUNT}"
fi
echo "Skipped files: ${SKIPPED_COUNT}"
