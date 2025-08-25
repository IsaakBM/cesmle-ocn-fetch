#!/bin/bash
set -euo pipefail

# Folder to save files
OUTDIR="$HOME/Desktop/z_esmLE_test"
mkdir -p "$OUTDIR"

# Base URL
BASE_URL="https://data-osdf.rda.ucar.edu/ncar/rda/d651027/cesmLE/CESM-CAM5-BGC-LE/ocn/proc/tseries/monthly/TEMP"

# Loop through 001 to 002 (test)
for n in 1 2; do
  i=$(printf "%03d" "$n")  # -> 001, 002
  echo "=== Member $i ==="

  single="b.e11.BRCP85C5CNBDRD.f09_g16.${i}.pop.h.TEMP.200601-210012.nc"
  single_url="${BASE_URL}/${single}"
  echo "Trying single: $single_url"
  if curl -fL -o "${OUTDIR}/${single}" "$single_url"; then
    echo "Downloaded ${single}"
    continue
  fi

  echo "Single not found; trying split parts…"
  for span in 200601-208012 208101-210012; do
    part="b.e11.BRCP85C5CNBDRD.f09_g16.${i}.pop.h.TEMP.${span}.nc"
    part_url="${BASE_URL}/${part}"
    echo "  → $part_url"
    curl -fL -o "${OUTDIR}/${part}" "$part_url"
  done
done

echo "Done. Files in ${OUTDIR}:"
ls -lh "${OUTDIR}"
