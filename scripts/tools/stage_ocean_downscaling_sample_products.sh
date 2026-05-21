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
#      layer and pelagic product outputs
#    - Preserve the viewer product layout:
#        layers/baseline/<variable>/<resolution>/*
#        layers/future/<variable>/<window>/<resolution>/*
#        pelagic/baseline/<variable>/<resolution>/*
#        pelagic/future/<variable>/<window>/<resolution>/*
#    - Restrict sample staging to one resolution, usually 0p05
#    - For future CESM physical variables with many ensemble members, keep only
#      one configured member, usually 001
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
#   STAGE_ROOT          : output root that will contain layers/ and pelagic/
#                         (default: /home/SB5/ocean_downscaling_sample_products_geotiff)
#   RESOLUTION          : resolution directory to copy
#                         (default: 0p05)
#   MEMBER              : future ensemble member retained for PHYSICAL_VARS
#                         (default: 001)
#   PHYSICAL_VARS       : space-separated variables filtered by MEMBER
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
# ==============================================================================

LAYERS_SOURCE_ROOT="${LAYERS_SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_layers_geotiff}"
PELAGIC_SOURCE_ROOT="${PELAGIC_SOURCE_ROOT:-/home/SB5/ocean_downscaling_products_pelagic_geotiff}"
STAGE_ROOT="${STAGE_ROOT:-/home/SB5/ocean_downscaling_sample_products_geotiff}"
RESOLUTION="${RESOLUTION:-0p05}"
MEMBER="${MEMBER:-001}"
PHYSICAL_VARS="${PHYSICAL_VARS:-thetao so uo}"
EXTENSIONS="${EXTENSIONS:-tif tiff}"
DRY_RUN="${DRY_RUN:-no}"
OVERWRITE="${OVERWRITE:-yes}"
STAGE_MANIFESTS="${STAGE_MANIFESTS:-yes}"

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

is_physical_var() {
  local var="$1"
  local physical_var

  for physical_var in ${PHYSICAL_VARS}; do
    if [[ "${var}" == "${physical_var}" ]]; then
      return 0
    fi
  done

  return 1
}

has_member() {
  local file_name="$1"
  local member="$2"

  [[ "${file_name}" == *".${member}."* ]]
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
  local rel_path family variable window resolution file_name dest
  local -a path_parts

  rel_path="${src#${src_root}/}"
  file_name="$(basename "${src}")"

  IFS='/' read -r -a path_parts <<<"${rel_path}"
  family="${path_parts[0]:-}"
  variable="${path_parts[1]:-}"

  if [[ "${family}" == "baseline" ]]; then
    resolution="${path_parts[2]:-}"
    if [[ "${resolution}" != "${RESOLUTION}" ]]; then
      return 0
    fi
    dest="${STAGE_ROOT}/${product_type}/baseline/${variable}/${resolution}/${file_name}"
  elif [[ "${family}" == "future" ]]; then
    window="${path_parts[2]:-}"
    resolution="${path_parts[3]:-}"

    # Some future physical products are exported directly under
    # future/<variable>/<window>/*.tif because their source tree has no
    # explicit 0p05 directory. They are still staged into the viewer's
    # future/<variable>/<window>/<resolution>/ layout. Do not apply this
    # fallback to biogeochemistry variables; their 0p05 files should live in
    # an explicit resolution directory.
    if [[ "${resolution}" == "${file_name}" ]]; then
      if ! is_physical_var "${variable}"; then
        return 0
      fi
      resolution="${RESOLUTION}"
    fi

    if [[ "${resolution}" != "${RESOLUTION}" ]]; then
      return 0
    fi
    dest="${STAGE_ROOT}/${product_type}/future/${variable}/${window}/${resolution}/${file_name}"
  else
    echo "[WARN] Skipping file outside baseline/future layout: ${rel_path}" >&2
    return 0
  fi

  if [[ "${family}" == "future" ]] && is_physical_var "${variable}" && ! has_member "${file_name}" "${MEMBER}"; then
    echo "[SKIP] ${product_type}/${rel_path} (keeping member ${MEMBER} only)"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
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
        \( -path "*/${RESOLUTION}/*.${extension}" -o -path "*/future/*/*/*.${extension}" \) \
        -type f \
        -print0 2>/dev/null
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
    "${STAGE_ROOT}" \
    "${RESOLUTION}" \
    "${MEMBER}" \
    "${PHYSICAL_VARS}" \
    "${DRY_RUN}" <<'PY'
import csv
import os
import sys

(
    layers_source_root,
    pelagic_source_root,
    stage_root,
    resolution,
    member,
    physical_vars_text,
    dry_run,
) = sys.argv[1:8]

physical_vars = set(physical_vars_text.split())


def has_member(file_name, member):
    return f".{member}." in file_name


def iter_manifest_rows(product_type, source_root):
    if not os.path.isdir(source_root):
        return

    for dirpath, _, file_names in os.walk(source_root):
        if "geotiff_manifest.csv" not in file_names:
            continue

        manifest = os.path.join(dirpath, "geotiff_manifest.csv")
        with open(manifest, newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                row["_manifest_file"] = manifest
                row["_product_type"] = product_type
                yield row


def staged_path_for_row(row, source_root):
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
    variable = parts[1]
    file_name = os.path.basename(abs_file)
    product_type = row["_product_type"]

    if family == "baseline":
        source_resolution = parts[2]
        if source_resolution != resolution:
            return None
        staged_rel = os.path.join(product_type, "baseline", variable, resolution, file_name)
    elif family == "future":
        window = parts[2]
        source_resolution = parts[3] if len(parts) >= 5 else resolution
        if len(parts) < 5 and variable not in physical_vars:
            return None
        if source_resolution != resolution:
            return None
        if variable in physical_vars and not has_member(file_name, member):
            return None
        staged_rel = os.path.join(product_type, "future", variable, window, resolution, file_name)
    else:
        return None

    return staged_rel


def write_manifest(name, rows):
    if not rows:
        print(f"[WARN] No manifest rows staged for: {name}", file=sys.stderr)
        return

    base_fields = [field for field in rows[0].keys() if not field.startswith("_")]
    extra_fields = ["product_type", "manifest_file", "staged_file", "staged_relative_path"]
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
for product_type, source_root in [
    ("layers", layers_source_root),
    ("pelagic", pelagic_source_root),
]:
    rows = []
    for row in iter_manifest_rows(product_type, source_root) or []:
        staged_rel = staged_path_for_row(row, source_root)
        if staged_rel is None:
            continue
        clean = {key: value for key, value in row.items() if not key.startswith("_")}
        clean["product_type"] = product_type
        clean["manifest_file"] = row["_manifest_file"]
        clean["staged_relative_path"] = staged_rel
        clean["staged_file"] = os.path.abspath(os.path.join(stage_root, staged_rel))
        rows.append(clean)

    by_product[product_type] = rows
    all_rows.extend(rows)

write_manifest("layers_geotiff_manifest.csv", by_product.get("layers", []))
write_manifest("pelagic_geotiff_manifest.csv", by_product.get("pelagic", []))
write_manifest("geotiff_manifest.csv", all_rows)
PY
}

echo "============================================================"
echo "Staging ocean downscaling sample products"
echo "LAYERS SOURCE  : ${LAYERS_SOURCE_ROOT}"
echo "PELAGIC SOURCE : ${PELAGIC_SOURCE_ROOT}"
echo "STAGE ROOT     : ${STAGE_ROOT}"
echo "RESOLUTION     : ${RESOLUTION}"
echo "MEMBER         : ${MEMBER}"
echo "PHYSICAL VARS  : ${PHYSICAL_VARS}"
echo "EXTENSIONS     : ${EXTENSIONS}"
echo "DRY RUN        : ${DRY_RUN}"
echo "OVERWRITE      : ${OVERWRITE}"
echo "STAGE MANIFESTS: ${STAGE_MANIFESTS}"
echo "============================================================"

if [[ "${DRY_RUN}" == "no" ]]; then
  mkdir -p "${STAGE_ROOT}/layers" "${STAGE_ROOT}/pelagic"
fi

COPIED_COUNT=0
SKIPPED_COUNT=0
stage_product_type "layers" "${LAYERS_SOURCE_ROOT}"
stage_product_type "pelagic" "${PELAGIC_SOURCE_ROOT}"
stage_manifests

echo
if [[ "${DRY_RUN}" == "yes" ]]; then
  echo "Dry run complete. Planned staged files: ${COPIED_COUNT}"
else
  echo "Done. Staged files copied: ${COPIED_COUNT}"
fi
echo "Skipped files: ${SKIPPED_COUNT}"
