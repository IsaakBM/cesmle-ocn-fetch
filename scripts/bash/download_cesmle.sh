#!/bin/bash
#
#SBATCH --job-name=cesmle_dl
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --time=02:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=cesmle_dl_%j.out
#SBATCH --error=cesmle_dl_%j.err

set -euo pipefail

# Output folder
OUTDIR="/home/sandbox-sparc/z_esmLE_test"
mkdir -p "$OUTDIR"

# Base URL
BASE_URL="https://data-osdf.rda.ucar.edu/ncar/rda/d651027/cesmLE/CESM-CAM5-BGC-LE/ocn/proc/tseries/monthly/TEMP"

echo "Starting CESM-LE TEMP downloads into $OUTDIR"

# Loop over ensemble members 001–035
for n in $(seq 1 35); do
  i=$(printf "%03d" "$n")   # 001, 002, …, 035
  echo "=== Member $i ==="

  single="b.e11.BRCP85C5CNBDRD.f09_g16.${i}.pop.h.TEMP.200601-210012.nc"
  single_url="${BASE_URL}/${single}"

  echo "Trying single file: $single_url"
  if curl -fL --retry 3 --retry-delay 2 -o "${OUTDIR}/${single}" "$single_url"; then
    echo "[ok] Downloaded ${single}"
    continue
  fi

  echo "Single not found; trying split parts…"
  for span in 200601-208012 208101-210012; do
    part="b.e11.BRCP85C5CNBDRD.f09_g16.${i}.pop.h.TEMP.${span}.nc"
    part_url="${BASE_URL}/${part}"
    echo "  -> $part_url"
    curl -fL --retry 3 --retry-delay 2 -o "${OUTDIR}/${part}" "$part_url"
  done
done

echo "All downloads complete. Files are in $OUTDIR"
