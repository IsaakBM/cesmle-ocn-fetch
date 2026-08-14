#!/usr/bin/env bash
# ==============================================================================
#  Create Cloud Optimized GeoTIFF sample products for Shiny/S3 tiler testing
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read the staged Shiny-viewer GeoTIFF sample product tree
#    - Mirror layers/ and depths/ into a parallel Cloud Optimized GeoTIFF tree
#    - Preserve integer-scaled stored values and GeoTIFF metadata
#    - Copy/update manifests for the COG tree
#    - Validate the expected product-tree shape, manifest counts, COG layout,
#      overviews, and known exclusion rules.
#
#  Intended to be run on Slurm-based HPC systems or an HPC login node.
# ==============================================================================

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   SOURCE_ROOT       : staged GeoTIFF sample tree
#                       (default: /home/SB5/ocean_downscaling_sample_products_geotiff)
#   COG_ROOT          : parallel COG sample tree
#                       (default: /home/SB5/ocean_downscaling_sample_products_cog)
#   RELATIVE_PREFIX   : optional subtree relative to SOURCE_ROOT to convert
#                       examples: layers, depths/future/ensemble/model_sd
#   FILE_LIST         : optional newline-delimited source file list
#   TMP_DIR           : temp/bookkeeping directory
#                       (default: ${TMPDIR:-/tmp}/create_cog_sample_products)
#   GDAL_TRANSLATE    : gdal_translate executable
#                       (default: gdal_translate)
#   GDALINFO          : gdalinfo executable
#                       (default: gdalinfo)
#   GDALADDO          : gdaladdo executable, used only by fallback path
#                       (default: gdaladdo)
#   RIO               : rio executable for optional rio cogeo validate
#                       (default: rio)
#   PYTHON            : Python interpreter for manifest validation
#                       (default: python3)
#   COMPRESS          : auto | DEFLATE | ZSTD | LZW | ...
#                       (default: auto)
#   BLOCKSIZE         : internal tile size for COG output
#                       (default: 256)
#   OVERVIEW_RESAMPLING
#                     : overview resampling method
#                       (default: NEAREST)
#   BIGTIFF           : GDAL BIGTIFF creation option
#                       (default: IF_SAFER)
#   NPROC             : files to convert in parallel
#                       (default: SLURM_CPUS_PER_TASK or 5)
#   OVERWRITE         : yes | no
#                       (default: no)
#   DRY_RUN           : yes | no
#                       (default: no)
#   CONVERT_FILES     : yes | no
#                       no -> only write manifests and run full-tree validation
#                       (default: yes)
#   WRITE_MANIFESTS   : yes | no
#                       (default: yes)
#   VALIDATE          : yes | no
#                       (default: yes)
#   VALIDATE_RIO      : auto | yes | no
#                       (default: auto)
#   EXPECT_LAYERS_ROWS
#                     : expected layers manifest rows
#                       (default: 7360)
#   EXPECT_DEPTHS_ROWS
#                     : expected depths manifest rows
#                       (default: 16648)
#   EXPECT_COMBINED_ROWS
#                     : expected combined manifest rows
#                       (default: 24008)
#   CHL_MAX_DEPTH_M   : maximum intended ensemble chl depth in meters
#                       (default: 541.089)
#   CHL_EXAMPLE_REL   : relative path for known chl validation example
# ==============================================================================

SOURCE_ROOT="${SOURCE_ROOT:-/home/SB5/ocean_downscaling_sample_products_geotiff}"
COG_ROOT="${COG_ROOT:-/home/SB5/ocean_downscaling_sample_products_cog}"
RELATIVE_PREFIX="${RELATIVE_PREFIX:-}"
FILE_LIST="${FILE_LIST:-}"
TMP_DIR="${TMP_DIR:-${TMPDIR:-/tmp}/create_cog_sample_products}"
GDAL_TRANSLATE="${GDAL_TRANSLATE:-gdal_translate}"
GDALINFO="${GDALINFO:-gdalinfo}"
GDALADDO="${GDALADDO:-gdaladdo}"
RIO="${RIO:-rio}"
PYTHON="${PYTHON:-python3}"
COMPRESS="${COMPRESS:-auto}"
BLOCKSIZE="${BLOCKSIZE:-256}"
OVERVIEW_RESAMPLING="${OVERVIEW_RESAMPLING:-NEAREST}"
BIGTIFF="${BIGTIFF:-IF_SAFER}"
NPROC="${NPROC:-${SLURM_CPUS_PER_TASK:-5}}"
OVERWRITE="${OVERWRITE:-no}"
DRY_RUN="${DRY_RUN:-no}"
CONVERT_FILES="${CONVERT_FILES:-yes}"
WRITE_MANIFESTS="${WRITE_MANIFESTS:-yes}"
VALIDATE="${VALIDATE:-yes}"
VALIDATE_RIO="${VALIDATE_RIO:-auto}"
EXPECT_LAYERS_ROWS="${EXPECT_LAYERS_ROWS:-7360}"
EXPECT_DEPTHS_ROWS="${EXPECT_DEPTHS_ROWS:-16648}"
EXPECT_COMBINED_ROWS="${EXPECT_COMBINED_ROWS:-24008}"
CHL_MAX_DEPTH_M="${CHL_MAX_DEPTH_M:-541.089}"
CHL_EXAMPLE_REL="${CHL_EXAMPLE_REL:-depths/future/ensemble/model_sd/ssp585/chl/2090-2100/0p05/ocean_downscaling_ensemble_model_sd_chl_ssp585_2090-2100_0p05_depth_0130p666m.tif}"

case "${OVERWRITE}" in yes|no) ;; *) echo "ERROR: OVERWRITE must be yes or no"; exit 1 ;; esac
case "${DRY_RUN}" in yes|no) ;; *) echo "ERROR: DRY_RUN must be yes or no"; exit 1 ;; esac
case "${CONVERT_FILES}" in yes|no) ;; *) echo "ERROR: CONVERT_FILES must be yes or no"; exit 1 ;; esac
case "${WRITE_MANIFESTS}" in yes|no) ;; *) echo "ERROR: WRITE_MANIFESTS must be yes or no"; exit 1 ;; esac
case "${VALIDATE}" in yes|no) ;; *) echo "ERROR: VALIDATE must be yes or no"; exit 1 ;; esac
case "${VALIDATE_RIO}" in auto|yes|no) ;; *) echo "ERROR: VALIDATE_RIO must be auto, yes, or no"; exit 1 ;; esac

if [[ ! -d "${SOURCE_ROOT}" ]]; then
  echo "ERROR: SOURCE_ROOT does not exist: ${SOURCE_ROOT}"
  exit 1
fi
if ! command -v "${GDAL_TRANSLATE}" >/dev/null 2>&1; then
  echo "ERROR: GDAL_TRANSLATE not found: ${GDAL_TRANSLATE}"
  exit 1
fi
if ! command -v "${GDALINFO}" >/dev/null 2>&1; then
  echo "ERROR: GDALINFO not found: ${GDALINFO}"
  exit 1
fi
if [[ "${WRITE_MANIFESTS}" == "yes" ]] || [[ "${VALIDATE}" == "yes" ]]; then
  if ! command -v "${PYTHON}" >/dev/null 2>&1; then
    echo "ERROR: PYTHON not found: ${PYTHON}"
    exit 1
  fi
fi

has_cog_driver() {
  "${GDAL_TRANSLATE}" --formats 2>/dev/null | grep -Eq '(^|[[:space:]])COG[[:space:]]'
}

compression_supported() {
  local codec="$1"
  "${GDAL_TRANSLATE}" --format COG 2>/dev/null | grep -Eiq "COMPRESS.*${codec}"
}

choose_compression() {
  local requested="$1"
  if [[ "${requested}" != "auto" ]]; then
    printf '%s\n' "${requested}"
    return 0
  fi
  if has_cog_driver; then
    for codec in ZSTD DEFLATE LZW; do
      if compression_supported "${codec}"; then
        printf '%s\n' "${codec}"
        return 0
      fi
    done
  fi
  printf '%s\n' "DEFLATE"
}

COG_COMPRESS="$(choose_compression "${COMPRESS}")"
USE_COG_DRIVER="no"
if has_cog_driver; then
  USE_COG_DRIVER="yes"
fi

mkdir -p "${COG_ROOT}" "${TMP_DIR}"
if [[ "${DRY_RUN}" == "no" ]]; then
  mkdir -p "${COG_ROOT}/layers" "${COG_ROOT}/depths"
  if [[ "${WRITE_MANIFESTS}" == "yes" ]]; then
    mkdir -p "${COG_ROOT}/manifests"
  fi
fi

include_source_file() {
  local file="$1" rel
  rel="${file#${SOURCE_ROOT}/}"
  case "${rel}" in
    layers/*.tif|layers/*.tiff|depths/*.tif|depths/*.tiff) ;;
    *) return 1 ;;
  esac
  case "$(basename "${file}")" in
    .DS_Store|._*|*.aux.xml) return 1 ;;
  esac
  [[ "${rel}" == *"/pelagic/"* || "${rel}" == pelagic/* ]] && return 1
  if [[ -n "${RELATIVE_PREFIX}" ]]; then
    [[ "${rel}" == "${RELATIVE_PREFIX}" || "${rel}" == "${RELATIVE_PREFIX}/"* ]] || return 1
  fi
  return 0
}

collect_files() {
  if [[ -n "${FILE_LIST}" ]]; then
    if [[ ! -f "${FILE_LIST}" ]]; then
      echo "ERROR: FILE_LIST does not exist: ${FILE_LIST}"
      exit 1
    fi
    while IFS= read -r file; do
      [[ -z "${file}" ]] && continue
      if [[ "${file}" != /* ]]; then
        file="${SOURCE_ROOT}/${file}"
      fi
      include_source_file "${file}" && printf '%s\n' "${file}"
    done < "${FILE_LIST}"
  else
    find "${SOURCE_ROOT}/layers" "${SOURCE_ROOT}/depths" \
      -type f \
      \( -name "*.tif" -o -name "*.tiff" \) \
      ! -name ".DS_Store" \
      ! -name "._*" \
      ! -name "*.aux.xml" \
      2>/dev/null | sort | while IFS= read -r file; do
        include_source_file "${file}" && printf '%s\n' "${file}"
      done
  fi
}

validate_one_cog() {
  local file="$1"
  local info
  info="$("${GDALINFO}" "${file}")"
  if ! grep -q "LAYOUT=COG" <<<"${info}"; then
    echo "ERROR: gdalinfo did not report LAYOUT=COG for: ${file}"
    return 1
  fi
  if ! grep -q "Overviews:" <<<"${info}"; then
    echo "ERROR: gdalinfo did not report internal overviews for: ${file}"
    return 1
  fi
  if ! "${GDALINFO}" --json "${file}" >/dev/null 2>&1; then
    "${GDALINFO}" -json "${file}" >/dev/null
  fi
  if [[ "${VALIDATE_RIO}" == "yes" ]] || { [[ "${VALIDATE_RIO}" == "auto" ]] && command -v "${RIO}" >/dev/null 2>&1; }; then
    "${RIO}" cogeo validate "${file}"
  fi
}

convert_one_file() {
  local src="$1"
  local rel dest tmp

  rel="${src#${SOURCE_ROOT}/}"
  dest="${COG_ROOT}/${rel}"
  tmp="${dest}.tmp.$$.tif"

  if [[ -f "${dest}" && "${OVERWRITE}" == "no" ]]; then
    echo "[SKIP] Existing COG: ${rel}"
    if [[ "${VALIDATE}" == "yes" ]]; then
      validate_one_cog "${dest}"
    fi
    return 0
  fi

  echo "[COG ] ${rel}"
  if [[ "${DRY_RUN}" == "yes" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${dest}")"
  rm -f "${tmp}"

  if [[ "${USE_COG_DRIVER}" == "yes" ]]; then
    "${GDAL_TRANSLATE}" \
      -of COG \
      -co "COMPRESS=${COG_COMPRESS}" \
      -co "BLOCKSIZE=${BLOCKSIZE}" \
      -co "BIGTIFF=${BIGTIFF}" \
      -co "OVERVIEWS=AUTO" \
      -co "RESAMPLING=${OVERVIEW_RESAMPLING}" \
      "${src}" \
      "${tmp}"
  else
    if ! command -v "${GDALADDO}" >/dev/null 2>&1; then
      echo "ERROR: GDAL COG driver is unavailable and GDALADDO was not found: ${GDALADDO}"
      return 1
    fi
    "${GDAL_TRANSLATE}" \
      -of GTiff \
      -co "COMPRESS=${COG_COMPRESS}" \
      -co "PREDICTOR=2" \
      -co "TILED=YES" \
      -co "BLOCKXSIZE=${BLOCKSIZE}" \
      -co "BLOCKYSIZE=${BLOCKSIZE}" \
      -co "BIGTIFF=${BIGTIFF}" \
      "${src}" \
      "${tmp}"
    "${GDALADDO}" -r "${OVERVIEW_RESAMPLING}" "${tmp}" 2 4 8 16
    cog_tmp="${tmp}.cog.tif"
    "${GDAL_TRANSLATE}" \
      -of GTiff \
      -co "COMPRESS=${COG_COMPRESS}" \
      -co "PREDICTOR=2" \
      -co "TILED=YES" \
      -co "COPY_SRC_OVERVIEWS=YES" \
      -co "BLOCKXSIZE=${BLOCKSIZE}" \
      -co "BLOCKYSIZE=${BLOCKSIZE}" \
      -co "BIGTIFF=${BIGTIFF}" \
      "${tmp}" \
      "${cog_tmp}"
    mv -f "${cog_tmp}" "${tmp}"
  fi

  if [[ "${VALIDATE}" == "yes" ]]; then
    validate_one_cog "${tmp}"
  fi
  mv -f "${tmp}" "${dest}"
}

write_manifests() {
  [[ "${WRITE_MANIFESTS}" == "yes" ]] || return 0

  echo
  echo "[STEP] Writing COG manifests"
  if [[ "${DRY_RUN}" == "yes" ]]; then
    echo "[DRY-RUN] Would write manifests under: ${COG_ROOT}/manifests"
    return 0
  fi
  mkdir -p "${COG_ROOT}/manifests"

  "${PYTHON}" - \
    "${SOURCE_ROOT}" \
    "${COG_ROOT}" \
    "${EXPECT_LAYERS_ROWS}" \
    "${EXPECT_DEPTHS_ROWS}" \
    "${EXPECT_COMBINED_ROWS}" <<'PY'
import csv
import os
import sys
import tempfile

source_root, cog_root, expect_layers, expect_depths, expect_combined = sys.argv[1:6]
expected = {
    "layers_geotiff_manifest.csv": int(expect_layers),
    "depths_geotiff_manifest.csv": int(expect_depths),
    "geotiff_manifest.csv": int(expect_combined),
}
manifest_dir = os.path.join(source_root, "manifests")
out_dir = os.path.join(cog_root, "manifests")
os.makedirs(out_dir, exist_ok=True)


def read_manifest(name):
    path = os.path.join(manifest_dir, name)
    if not os.path.isfile(path):
        raise SystemExit(f"Missing source manifest: {path}")
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader), list(reader.fieldnames or [])


def row_points_to_kept_tree(row):
    pieces = [
        row.get("product_type", ""),
        row.get("staged_relative_path", ""),
        row.get("relative_path", ""),
        row.get("source_relative_path", ""),
        row.get("geotiff_file", ""),
        row.get("staged_file", ""),
    ]
    text = "/".join(str(piece) for piece in pieces)
    if "pelagic" in text:
        return False
    rel = row.get("staged_relative_path") or row.get("relative_path") or row.get("source_relative_path")
    return rel.startswith("layers/") or rel.startswith("depths/")


def update_row(row):
    rel = row.get("staged_relative_path") or row.get("relative_path") or row.get("source_relative_path")
    if rel:
        row["staged_relative_path"] = rel
        cog_path = os.path.abspath(os.path.join(cog_root, rel))
        if "geotiff_file" in row:
            row["geotiff_file"] = cog_path
        if "staged_file" in row:
            row["staged_file"] = cog_path
    row["storage_format"] = "cog"
    return row


def write_manifest(name, rows, fields):
    out_path = os.path.join(out_dir, name)
    if "storage_format" not in fields:
        fields = fields + ["storage_format"]
    for field in ("staged_relative_path", "geotiff_file", "staged_file"):
        if any(field in row for row in rows) and field not in fields:
            fields.append(field)
    fd, tmp_path = tempfile.mkstemp(prefix=f".{name}.", suffix=".tmp", dir=out_dir)
    os.close(fd)
    try:
        with open(tmp_path, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(rows)
        os.replace(tmp_path, out_path)
    finally:
        try:
            os.remove(tmp_path)
        except FileNotFoundError:
            pass
    print(f"[MANIFEST] {out_path} rows={len(rows)}")


for name, expected_rows in expected.items():
    rows, fields = read_manifest(name)
    rows = [update_row(dict(row)) for row in rows if row_points_to_kept_tree(row)]
    if len(rows) != expected_rows:
        raise SystemExit(f"{name} row count mismatch: got {len(rows)}, expected {expected_rows}")
    write_manifest(name, rows, fields)
PY
}

validate_tree_and_manifests() {
  [[ "${VALIDATE}" == "yes" ]] || return 0

  echo
  echo "[STEP] Validating COG product tree"
  "${PYTHON}" - \
    "${COG_ROOT}" \
    "${EXPECT_LAYERS_ROWS}" \
    "${EXPECT_DEPTHS_ROWS}" \
    "${EXPECT_COMBINED_ROWS}" \
    "${CHL_MAX_DEPTH_M}" \
    "${CHL_EXAMPLE_REL}" <<'PY'
import csv
import math
import os
import re
import sys

cog_root, expect_layers, expect_depths, expect_combined, chl_max_depth, chl_example_rel = sys.argv[1:7]
expected_counts = {
    "layers_geotiff_manifest.csv": int(expect_layers),
    "depths_geotiff_manifest.csv": int(expect_depths),
    "geotiff_manifest.csv": int(expect_combined),
}
allowed_top = {"layers", "depths", "manifests"}
banned = ("pelagic", "rcp85", "cesm_f09_g16", "legacy_downscaled_rcp85")
depth_limit = float(chl_max_depth)

top = set(os.listdir(cog_root))
extra = top - allowed_top
missing = allowed_top - top
if extra or missing:
    raise SystemExit(f"Unexpected top-level COG tree entries. extra={sorted(extra)} missing={sorted(missing)}")

for dirpath, dirnames, filenames in os.walk(cog_root):
    dirnames[:] = [name for name in dirnames if not name.startswith("tmp_create_cog")]
    rel_dir = os.path.relpath(dirpath, cog_root)
    rel_dir = "" if rel_dir == "." else rel_dir
    for name in filenames:
        rel = os.path.join(rel_dir, name) if rel_dir else name
        if name == ".DS_Store" or name.startswith("._") or name.endswith(".aux.xml"):
            raise SystemExit(f"Excluded sidecar/junk file found: {rel}")
        for token in banned:
            if token in rel:
                raise SystemExit(f"Banned path token found in COG tree: {token}: {rel}")

for name, expected in expected_counts.items():
    path = os.path.join(cog_root, "manifests", name)
    if not os.path.isfile(path):
        raise SystemExit(f"Missing COG manifest: {path}")
    with open(path, newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != expected:
        raise SystemExit(f"{name} row count mismatch: got {len(rows)}, expected {expected}")
    for row in rows:
        text = "/".join(str(v) for v in row.values())
        for token in banned:
            if token in text:
                raise SystemExit(f"Banned token {token} found in manifest {name}")
        if row.get("storage_format") != "cog":
            raise SystemExit(f"storage_format is not cog in {name}")

max_bad = []
depth_pattern = re.compile(r"depth_([0-9]+p[0-9]+)m")
for dirpath, _dirnames, filenames in os.walk(os.path.join(cog_root, "depths", "future", "ensemble")):
    path_parts = set(os.path.relpath(dirpath, cog_root).split(os.sep))
    if "chl" not in path_parts:
        continue
    for name in filenames:
        if not name.endswith((".tif", ".tiff")):
            continue
        match = depth_pattern.search(name)
        if not match:
            continue
        depth_m = float(match.group(1).replace("p", "."))
        if depth_m > depth_limit + 1e-9:
            max_bad.append(os.path.join(os.path.relpath(dirpath, cog_root), name))
if max_bad:
    raise SystemExit(
        f"Ensemble chl depth products deeper than {depth_limit:g} m found; first={max_bad[0]}"
    )

example_path = os.path.join(cog_root, chl_example_rel)
if not os.path.isfile(example_path):
    raise SystemExit(f"Missing chl validation example: {example_path}")

combined = os.path.join(cog_root, "manifests", "geotiff_manifest.csv")
with open(combined, newline="") as handle:
    rows = list(csv.DictReader(handle))
example_rows = [
    row for row in rows
    if row.get("staged_relative_path") == chl_example_rel
    or row.get("geotiff_file") == os.path.abspath(example_path)
    or row.get("staged_file") == os.path.abspath(example_path)
]
if not example_rows:
    raise SystemExit(f"Chl validation example is missing from combined manifest: {chl_example_rel}")
row = example_rows[0]
scale_factor = float(row.get("scale_factor", "nan"))
max_real = float(row.get("max_real", "nan"))
if not math.isfinite(scale_factor) or abs(scale_factor - 10000.0) > 1e-6:
    raise SystemExit(f"Unexpected chl scale_factor for example: {scale_factor}")
if not math.isfinite(max_real) or abs(max_real - 1.1425) > 0.01:
    raise SystemExit(f"Unexpected chl max_real for example: {max_real}; expected around 1.1425")

print("[VALID] tree shape, manifests, exclusions, chl depths, and chl example metadata passed")
PY
}

echo "============================================================"
echo "Creating COG sample products"
echo "SOURCE ROOT   : ${SOURCE_ROOT}"
echo "COG ROOT      : ${COG_ROOT}"
echo "REL PREFIX    : ${RELATIVE_PREFIX:-<all layers/depths>}"
echo "TMP DIR       : ${TMP_DIR}"
echo "GDAL COG      : ${USE_COG_DRIVER}"
echo "COMPRESS      : ${COG_COMPRESS}"
echo "BLOCKSIZE     : ${BLOCKSIZE}"
echo "OVERVIEWS     : AUTO, ${OVERVIEW_RESAMPLING}"
echo "PARALLEL FILES: ${NPROC}"
echo "OVERWRITE     : ${OVERWRITE}"
echo "DRY RUN       : ${DRY_RUN}"
echo "CONVERT FILES : ${CONVERT_FILES}"
echo "MANIFESTS     : ${WRITE_MANIFESTS}"
echo "VALIDATE      : ${VALIDATE}"
echo "RIO VALIDATE  : ${VALIDATE_RIO}"
echo "============================================================"

if [[ "${CONVERT_FILES}" == "yes" ]]; then
  files=()
  while IFS= read -r file; do
    files+=("${file}")
  done < <(collect_files)
  if (( ${#files[@]} == 0 )); then
    echo "ERROR: No GeoTIFF files found under SOURCE_ROOT for RELATIVE_PREFIX=${RELATIVE_PREFIX:-<all>}"
    exit 1
  fi

  export SOURCE_ROOT COG_ROOT GDAL_TRANSLATE GDALINFO GDALADDO RIO COG_COMPRESS BLOCKSIZE OVERVIEW_RESAMPLING BIGTIFF
  export OVERWRITE DRY_RUN VALIDATE VALIDATE_RIO USE_COG_DRIVER
  export -f validate_one_cog convert_one_file

  set +e
  printf '%s\0' "${files[@]}" \
    | xargs -0 -n 1 -P "${NPROC}" bash -c 'set -euo pipefail; convert_one_file "$1"' _
  xargs_status=$?
  set -e

  if (( xargs_status != 0 )); then
    echo "ERROR: One or more COG conversions failed."
    exit "${xargs_status}"
  fi
fi

if [[ -z "${RELATIVE_PREFIX}" && -z "${FILE_LIST}" ]]; then
  write_manifests
  validate_tree_and_manifests
else
  echo
  echo "[INFO] Subtree/file-list run complete; manifest and full-tree validation are skipped for partial runs."
fi

echo
echo "COG sample product workflow completed."
