#!/bin/bash
#
#SBATCH --job-name=cesmle_list_par
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8        # <- parallelism here
#SBATCH --time=03:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=cesmle_list_par_%j.out
#SBATCH --error=cesmle_list_par_%j.err

set -euo pipefail

# ---------- CONFIG ----------
OUTROOT="/home/sandbox-sparc/z_esmLE_test"
VARS=(TEMP SALT O2 UVEL)
BASE_ROOT="https://data-osdf.rda.ucar.edu/ncar/rda/d651027/cesmLE/CESM-CAM5-BGC-LE/ocn/proc/tseries/monthly"
CPUS="${SLURM_CPUS_PER_TASK:-4}"

# regex for members 001–035
MEM_RE='(00[1-9]|0[1-2][0-9]|03[0-5])'

mkdir -p "$OUTROOT"

# Build tasks list: each line "URL DEST"
TASKS="$(mktemp)"
trap 'rm -f "$TASKS"' EXIT

echo "[info] Output root: $OUTROOT"
echo "[info] Parallel workers: $CPUS"

for var in "${VARS[@]}"; do
  OUTDIR="${OUTROOT}/${var}"
  INDEX_URL="${BASE_ROOT}/${var}/"
  mkdir -p "$OUTDIR"

  echo "============================"
  echo "[var] $var"
  echo "      Index: $INDEX_URL"
  echo "      Out:   $OUTDIR"

  # Fetch directory listing once
  html="$(curl -sL "$INDEX_URL" || true)"

  # Extract all matching filenames for 001–035 for this var
  # Example: b.e11.BRCP85C5CNBDRD.f09_g16.001.pop.h.TEMP.200601-208012.nc
  mapfile -t files < <(echo "$html" \
    | grep -oE "b\.e11\.BRCP85C5CNBDRD\.f09_g16\.${MEM_RE}\.pop\.h\.${var}\.[^\"]+\.nc" \
    | sort -u)

  MANIFEST="${OUTDIR}/manifest_${var}.txt"
  : > "$MANIFEST"

  if [[ "${#files[@]}" -eq 0 ]]; then
    echo "      [warn] no listing entries found for ${var}"
    continue
  fi

  echo "      [list] ${#files[@]} files found"
  for fname in "${files[@]}"; do
    echo "        $fname" | tee -a "$MANIFEST" >/dev/null
    url="${INDEX_URL}${fname}"
    dest="${OUTDIR}/${fname}"
    # Skip if already downloaded
    if [[ -f "$dest" ]]; then
      echo "      [skip] exists: $fname"
      continue
    fi
    # Queue download task: URL DEST
    echo "$url $dest" >> "$TASKS"
  done
  echo "      [done] manifest: $MANIFEST"
done

# Parallel downloads
if [[ -s "$TASKS" ]]; then
  echo "============================"
  echo "[info] Starting parallel downloads…"
  # shellcheck disable=SC2016
  xargs -P "$CPUS" -n 2 bash -c 'curl -fL --retry 3 --retry-delay 2 -o "$2" "$1"' _ < "$TASKS"
  echo "[info] Downloads complete."
else
  echo "[info] Nothing to download (all files present or no matches)."
fi

echo "[done] Check $OUTROOT"
