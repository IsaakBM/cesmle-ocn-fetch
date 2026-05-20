#!/usr/bin/env bash
# ==============================================================================
#  Curated ocean downscaling NetCDF to integer-scaled GeoTIFF exporter
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Read curated aggregated 2D NetCDF products from a mirrored product tree
#    - Mirror the same structure into a compressed GeoTIFF tree
#    - Encode floating-point values as integer-scaled rasters:
#        stored_value = round(real_value * scale_factor)
#        real_value   = stored_value / scale_factor
#    - Write a manifest that records scale factors, data types, nodata values,
#      units, and source/output files for Shiny/terra use.
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=to_geotiff
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=6
#SBATCH --mem=128G
#SBATCH -t 1-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/to_geotiff_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/to_geotiff_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail
shopt -s nullglob

# ==============================================================================
# Optional env vars
#   IN_ROOT        : NetCDF input root
#   OUT_ROOT       : mirrored GeoTIFF output root
#   TMP_DIR        : temp / bookkeeping directory
#                    (default: <OUT_ROOT>/tmp_export_geotiff)
#   GEOTIFF_PYTHON : Python interpreter with numpy and xarray available.
#                    GeoTIFF writing uses rasterio, GDAL Python bindings, or
#                    command-line gdal_translate when available.
#                    (default: /home/ibrito/venvs/parquet_export/bin/python)
#   GDAL_TRANSLATE  : gdal_translate executable used when Python GeoTIFF
#                    writers are unavailable
#                    (default: gdal_translate)
#   SCALE_FACTORS  : comma-separated scale overrides, e.g.
#                    thetao=100,so=100,o2=10,chl=10000
#   DEFAULT_SCALE  : scale factor used when no variable-specific match exists
#                    (default: 100)
#   ENCODE_DTYPE   : auto | int16 | int32
#                    auto -> use Int16 when values fit, otherwise Int32
#                    (default: auto)
#   COMPRESS       : GeoTIFF compression codec
#                    (default: DEFLATE)
#   NPROC          : number of files to process in parallel
#                    (default: SLURM_CPUS_PER_TASK or 6)
# ==============================================================================
IN_ROOT="${IN_ROOT:-/home/SB5/ocean_downscaling_products_layers}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/ocean_downscaling_products_layers_geotiff}"
TMP_DIR="${TMP_DIR:-${OUT_ROOT}/tmp_export_geotiff}"
GEOTIFF_PYTHON="${GEOTIFF_PYTHON:-/home/ibrito/venvs/parquet_export/bin/python}"
GDAL_TRANSLATE="${GDAL_TRANSLATE:-gdal_translate}"
SCALE_FACTORS="${SCALE_FACTORS:-thetao=100,TEMP=100,so=100,SALT=100,uo=100,UVEL=100,o2=10,O2=10,chl=10000,CHL=10000}"
DEFAULT_SCALE="${DEFAULT_SCALE:-100}"
ENCODE_DTYPE="${ENCODE_DTYPE:-auto}"
COMPRESS="${COMPRESS:-DEFLATE}"
NPROC="${NPROC:-${SLURM_CPUS_PER_TASK:-6}}"

if [[ ! -d "${IN_ROOT}" ]]; then
  echo "ERROR: IN_ROOT does not exist: ${IN_ROOT}"
  exit 1
fi

if [[ ! -x "${GEOTIFF_PYTHON}" ]]; then
  echo "ERROR: GEOTIFF_PYTHON is not executable: ${GEOTIFF_PYTHON}"
  exit 1
fi

case "${ENCODE_DTYPE}" in
  auto|int16|int32) ;;
  *)
    echo "ERROR: ENCODE_DTYPE must be auto, int16, or int32"
    exit 1
    ;;
esac

mkdir -p "${OUT_ROOT}" "${TMP_DIR}" "${TMP_DIR}/manifest_parts"
rm -f "${TMP_DIR}/manifest_parts"/*.csv

"${GEOTIFF_PYTHON}" - <<'PY'
import importlib
import os
import shutil

mods = ["numpy", "xarray"]
missing = []
for name in mods:
    try:
        importlib.import_module(name)
    except Exception as exc:
        missing.append(f"{name}: {exc}")

writer_ok = False
writer_errors = []
try:
    importlib.import_module("rasterio")
    writer_ok = True
except Exception as exc:
    writer_errors.append(f"rasterio: {exc}")

try:
    importlib.import_module("osgeo.gdal")
    importlib.import_module("osgeo.osr")
    writer_ok = True
except Exception as exc:
    writer_errors.append(f"osgeo.gdal/osgeo.osr: {exc}")

gdal_translate = os.environ.get("GDAL_TRANSLATE", "gdal_translate")
if shutil.which(gdal_translate):
    writer_ok = True
else:
    writer_errors.append(f"{gdal_translate}: executable not found")

if not writer_ok:
    missing.append("Need rasterio, GDAL Python bindings, or gdal_translate:\n" + "\n".join(writer_errors))

backend_ok = False
for backend in ["netCDF4", "h5netcdf"]:
    try:
        importlib.import_module(backend)
        backend_ok = True
        break
    except Exception:
        pass

if not backend_ok:
    missing.append("Need at least one xarray NetCDF backend: netCDF4 or h5netcdf")

if missing:
    raise SystemExit("Missing Python dependencies for GeoTIFF export:\n" + "\n".join(missing))
PY

process_one_file() {
  local infile="$1"
  local rel_path rel_dir base outfile manifest_key manifest_part

  rel_path="${infile#${IN_ROOT}/}"
  rel_dir="$(dirname "${rel_path}")"
  base="$(basename "${infile}" .nc)"
  outfile="${OUT_ROOT}/${rel_dir}/${base}.tif"
  manifest_key="$(echo "${rel_path}" | tr '/' '_' | tr -cd '[:alnum:]_.-')"
  manifest_part="${TMP_DIR}/manifest_parts/${manifest_key}.$$.csv"

  mkdir -p "$(dirname "${outfile}")"
  rm -f "${outfile}"

  echo
  echo "[START] ${rel_path}"

  "${GEOTIFF_PYTHON}" - \
    "${infile}" \
    "${outfile}" \
    "${rel_path}" \
    "${SCALE_FACTORS}" \
    "${DEFAULT_SCALE}" \
    "${ENCODE_DTYPE}" \
    "${COMPRESS}" \
    "${manifest_part}" \
    "${TMP_DIR}/$(basename "${manifest_part}" .csv).encoded.tmp.nc" <<'PY'
import csv
import os
import re
import shutil
import subprocess
import sys
import numpy as np
import xarray as xr

try:
    import rasterio
    from rasterio.transform import from_origin
except Exception:
    rasterio = None
    from_origin = None

try:
    from osgeo import gdal, osr
except Exception:
    gdal = None
    osr = None

(
    infile,
    outfile,
    rel_path,
    scale_factors_text,
    default_scale_text,
    encode_dtype,
    compress,
    manifest_part,
    tmp_encoded_nc,
) = sys.argv[1:10]

preferred_xy = [
    ("lon", "lat"),
    ("longitude", "latitude"),
    ("x", "y"),
]

ignored_vars = {"time_bnds", "lat_bnds", "lon_bnds", "depth_bnds"}
nodata_by_dtype = {"int16": -32768, "int32": -2147483648}
limits_by_dtype = {
    "int16": (-32767, 32767),
    "int32": (-2147483647, 2147483647),
}
if rasterio is None and gdal is None:
    gdal_translate = os.environ.get("GDAL_TRANSLATE", "gdal_translate")
    if shutil.which(gdal_translate) is None:
        raise SystemExit("Need rasterio, GDAL Python bindings, or command-line gdal_translate for GeoTIFF writing")
else:
    gdal_translate = os.environ.get("GDAL_TRANSLATE", "gdal_translate")

def parse_scale_factors(text):
    values = {}
    for item in text.split(","):
        item = item.strip()
        if not item:
            continue
        if "=" not in item:
            raise SystemExit(f"Bad SCALE_FACTORS item: {item}")
        key, value = item.split("=", 1)
        values[key.strip().lower()] = float(value)
    return values

def choose_main_var(ds):
    data_vars = [v for v in ds.data_vars if v not in ignored_vars]
    if not data_vars:
        raise SystemExit(f"No usable data variable found in {infile}")
    for candidate in data_vars:
        if ds[candidate].ndim >= 2:
            return candidate
    return data_vars[0]

def choose_xy(ds, da):
    for x_candidate, y_candidate in preferred_xy:
        if x_candidate in ds and y_candidate in ds:
            return x_candidate, y_candidate
    if "lon" in da.coords and "lat" in da.coords:
        return "lon", "lat"
    raise SystemExit(f"Could not identify x/y coordinates in {infile}")

def axis_spacing(values, name):
    diffs = np.diff(values)
    if diffs.size == 0:
        raise SystemExit(f"{name} coordinate must contain more than one value: {infile}")
    step = float(np.nanmedian(np.abs(diffs)))
    if not np.allclose(np.abs(diffs), step, rtol=1e-4, atol=1e-8):
        raise SystemExit(f"{name} coordinate is not evenly spaced: {infile}")
    return step

def detect_variable_key(path, main_var):
    tokens = [main_var]
    tokens.extend(re.split(r"[/_.-]+", path))
    known = ["thetao", "temp", "so", "salt", "uo", "uvel", "o2", "chl"]
    for token in tokens:
        low = token.lower()
        if low in known:
            return token
    return main_var

scale_factors = parse_scale_factors(scale_factors_text)
default_scale = float(default_scale_text)

with xr.open_dataset(infile) as ds:
    main_var = choose_main_var(ds)
    da = ds[main_var].squeeze(drop=True)

    x_name, y_name = choose_xy(ds, da)
    xcoord = ds[x_name]
    ycoord = ds[y_name]

    if x_name in da.dims and y_name in da.dims:
        da = da.transpose(y_name, x_name)

    if xcoord.ndim != 1 or ycoord.ndim != 1:
        raise SystemExit(
            f"GeoTIFF export requires 1D regular lon/lat or x/y coordinates; "
            f"got {x_name}.ndim={xcoord.ndim}, {y_name}.ndim={ycoord.ndim} in {infile}"
        )

    values = np.asarray(da.values, dtype=np.float64)
    if values.ndim != 2:
        raise SystemExit(f"Expected a 2D variable in {infile}, got ndim={values.ndim}")

    x = np.asarray(xcoord.values, dtype=np.float64)
    y = np.asarray(ycoord.values, dtype=np.float64)
    if values.shape != (y.size, x.size):
        raise SystemExit(
            f"Shape mismatch in {infile}: data={values.shape}, "
            f"{y_name}={y.size}, {x_name}={x.size}"
        )

    x_step = axis_spacing(x, x_name)
    y_step = axis_spacing(y, y_name)

    if x[0] > x[-1]:
        x = x[::-1]
        values = values[:, ::-1]
    if y[0] < y[-1]:
        y = y[::-1]
        values = values[::-1, :]

    west = float(x.min() - x_step / 2.0)
    north = float(y.max() + y_step / 2.0)
    geotransform = (west, x_step, 0.0, north, 0.0, -y_step)
    rasterio_transform = from_origin(west, north, x_step, y_step) if from_origin is not None else None

    variable_key = detect_variable_key(rel_path, main_var)
    scale_factor = scale_factors.get(variable_key.lower(), default_scale)
    if not np.isfinite(scale_factor) or scale_factor <= 0:
        raise SystemExit(f"Scale factor must be positive for {infile}: {scale_factor}")

    encoded = np.rint(values * scale_factor)
    valid = np.isfinite(encoded)

    valid_min = float(np.nanmin(values)) if np.isfinite(values).any() else np.nan
    valid_max = float(np.nanmax(values)) if np.isfinite(values).any() else np.nan
    encoded_min = float(np.nanmin(encoded)) if valid.any() else np.nan
    encoded_max = float(np.nanmax(encoded)) if valid.any() else np.nan

    if encode_dtype == "auto":
        lo16, hi16 = limits_by_dtype["int16"]
        dtype_name = "int16"
        if valid.any() and (encoded_min < lo16 or encoded_max > hi16):
            dtype_name = "int32"
    else:
        dtype_name = encode_dtype

    lo, hi = limits_by_dtype[dtype_name]
    if valid.any() and (encoded_min < lo or encoded_max > hi):
        raise SystemExit(
            f"Encoded values exceed {dtype_name} range in {infile}: "
            f"encoded_min={encoded_min}, encoded_max={encoded_max}, "
            f"scale_factor={scale_factor}"
        )

    nodata = nodata_by_dtype[dtype_name]
    out_array = np.full(values.shape, nodata, dtype=np.dtype(dtype_name))
    out_array[valid] = encoded[valid].astype(dtype_name)

    crs = None
    if x_name.lower() in {"lon", "longitude"} and y_name.lower() in {"lat", "latitude"}:
        crs = "EPSG:4326"

    units = str(da.attrs.get("units", ""))
    os.makedirs(os.path.dirname(outfile), exist_ok=True)
    if rasterio is not None:
        profile = {
            "driver": "GTiff",
            "height": out_array.shape[0],
            "width": out_array.shape[1],
            "count": 1,
            "dtype": dtype_name,
            "crs": crs,
            "transform": rasterio_transform,
            "nodata": nodata,
            "compress": compress,
            "predictor": 2,
            "tiled": True,
            "blockxsize": 256,
            "blockysize": 256,
            "BIGTIFF": "IF_SAFER",
        }
        with rasterio.open(outfile, "w", **profile) as dst:
            dst.write(out_array, 1)
            dst.update_tags(
                variable=main_var,
                units=units,
                scale_factor=str(scale_factor),
                offset="0",
                decode_formula="real_value = stored_value / scale_factor",
                source_netcdf=os.path.abspath(infile),
            )
            dst.update_tags(
                1,
                variable=main_var,
                units=units,
                scale_factor=str(scale_factor),
                offset="0",
            )
    else:
        if gdal is not None:
            gdal_dtype_by_name = {
                "int16": gdal.GDT_Int16,
                "int32": gdal.GDT_Int32,
            }
            driver = gdal.GetDriverByName("GTiff")
            options = [
                f"COMPRESS={compress}",
                "PREDICTOR=2",
                "TILED=YES",
                "BLOCKXSIZE=256",
                "BLOCKYSIZE=256",
                "BIGTIFF=IF_SAFER",
            ]
            dataset = driver.Create(
                outfile,
                out_array.shape[1],
                out_array.shape[0],
                1,
                gdal_dtype_by_name[dtype_name],
                options=options,
            )
            if dataset is None:
                raise SystemExit(f"Could not create GeoTIFF: {outfile}")

            dataset.SetGeoTransform(geotransform)
            if crs == "EPSG:4326":
                srs = osr.SpatialReference()
                srs.ImportFromEPSG(4326)
                dataset.SetProjection(srs.ExportToWkt())

            dataset.SetMetadata(
                {
                    "variable": main_var,
                    "units": units,
                    "scale_factor": str(scale_factor),
                    "offset": "0",
                    "decode_formula": "real_value = stored_value / scale_factor",
                    "source_netcdf": os.path.abspath(infile),
                }
            )
            band = dataset.GetRasterBand(1)
            band.SetNoDataValue(nodata)
            band.SetMetadata({"variable": main_var, "units": units, "scale_factor": str(scale_factor), "offset": "0"})
            band.WriteArray(out_array)
            band.FlushCache()
            dataset.FlushCache()
            dataset = None
        else:
            tmp_da = xr.DataArray(
                out_array,
                dims=(y_name, x_name),
                coords={y_name: y, x_name: x},
                name=main_var,
                attrs={
                    "units": units,
                    "scale_factor_for_app": scale_factor,
                    "decode_formula": "real_value = stored_value / scale_factor",
                },
            )
            tmp_ds = tmp_da.to_dataset()
            tmp_ds.attrs["source_netcdf"] = os.path.abspath(infile)
            tmp_ds.attrs["crs"] = crs or ""
            encoding = {main_var: {"dtype": dtype_name, "_FillValue": nodata}}
            os.makedirs(os.path.dirname(tmp_encoded_nc), exist_ok=True)
            tmp_ds.to_netcdf(tmp_encoded_nc, encoding=encoding)

            src = f'NETCDF:"{tmp_encoded_nc}":{main_var}'
            cmd = [
                gdal_translate,
                "-of",
                "GTiff",
                "-a_nodata",
                str(nodata),
                "-mo",
                f"variable={main_var}",
                "-mo",
                f"units={units}",
                "-mo",
                f"scale_factor={scale_factor}",
                "-mo",
                "offset=0",
                "-mo",
                "decode_formula=real_value = stored_value / scale_factor",
                "-mo",
                f"source_netcdf={os.path.abspath(infile)}",
                "-co",
                f"COMPRESS={compress}",
                "-co",
                "PREDICTOR=2",
                "-co",
                "TILED=YES",
                "-co",
                "BLOCKXSIZE=256",
                "-co",
                "BLOCKYSIZE=256",
                "-co",
                "BIGTIFF=IF_SAFER",
                src,
                outfile,
            ]
            if crs == "EPSG:4326":
                cmd[1:1] = ["-a_srs", "EPSG:4326"]
            subprocess.run(cmd, check=True)
            try:
                os.remove(tmp_encoded_nc)
            except OSError:
                pass

    row = {
        "source_file": os.path.abspath(infile),
        "relative_path": rel_path,
        "geotiff_file": os.path.abspath(outfile),
        "variable": main_var,
        "variable_key": variable_key,
        "units": units,
        "scale_factor": scale_factor,
        "offset": 0,
        "encoded_dtype": dtype_name,
        "nodata": nodata,
        "min_real": valid_min,
        "max_real": valid_max,
        "min_encoded": encoded_min,
        "max_encoded": encoded_max,
        "compress": compress,
        "crs": crs or "",
    }

    with open(manifest_part, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row.keys()))
        writer.writeheader()
        writer.writerow(row)
PY

  echo "[DONE ] ${outfile}"
}

echo "============================================================"
echo "Starting NetCDF to integer-scaled GeoTIFF export"
echo "IN ROOT        : ${IN_ROOT}"
echo "OUT ROOT       : ${OUT_ROOT}"
echo "TMP DIR        : ${TMP_DIR}"
echo "GEOTIFF PYTHON : ${GEOTIFF_PYTHON}"
echo "GDAL TRANSLATE : ${GDAL_TRANSLATE}"
echo "SCALE FACTORS  : ${SCALE_FACTORS}"
echo "DEFAULT SCALE  : ${DEFAULT_SCALE}"
echo "ENCODE DTYPE   : ${ENCODE_DTYPE}"
echo "COMPRESS       : ${COMPRESS}"
echo "PARALLEL FILES : ${NPROC}"
echo "============================================================"

mapfile -t files < <(find "${IN_ROOT}" -type f -name "*.nc" | sort)
if (( ${#files[@]} == 0 )); then
  echo "ERROR: No NetCDF files found under: ${IN_ROOT}"
  exit 1
fi

"${GEOTIFF_PYTHON}" - "${files[0]}" <<'PY'
import sys
import xarray as xr

infile = sys.argv[1]
try:
    with xr.open_dataset(infile):
        pass
except Exception as exc:
    raise SystemExit(
        "GeoTIFF export preflight failed before processing files.\n"
        f"Could not open NetCDF input with the configured Python environment: {infile}\n"
        f"Reason: {exc}"
    )
PY

export IN_ROOT OUT_ROOT TMP_DIR GEOTIFF_PYTHON GDAL_TRANSLATE SCALE_FACTORS DEFAULT_SCALE ENCODE_DTYPE COMPRESS
export -f process_one_file

printf '%s\0' "${files[@]}" \
  | xargs -0 -n 1 -P "${NPROC}" bash -c 'process_one_file "$1"' _

manifest="${OUT_ROOT}/geotiff_manifest.csv"
first_part="$(find "${TMP_DIR}/manifest_parts" -type f -name "*.csv" | sort | head -n 1)"
if [[ -z "${first_part}" ]]; then
  echo "ERROR: No manifest parts were created"
  exit 1
fi

head -n 1 "${first_part}" > "${manifest}"
find "${TMP_DIR}/manifest_parts" -type f -name "*.csv" | sort | while read -r part; do
  tail -n +2 "${part}" >> "${manifest}"
done

echo
echo "Manifest written: ${manifest}"
echo "All NetCDF to integer-scaled GeoTIFF exports completed."
