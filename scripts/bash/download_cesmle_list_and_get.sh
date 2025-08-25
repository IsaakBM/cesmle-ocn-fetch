#!/bin/bash
#
#SBATCH --job-name=cesmle_list_get
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --time=04:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=cesmle_list_get_%j.out
#SBATCH --error=cesmle_list_get_%j.err

set -euo pipefail

# -------- CONFIG --------
OUTROOT="/home/sandbox-sparc/z_esmLE_test"
VARS=(TEMP SALT O2 UVEL)
MEMBERS=$(seq -w 001 035)
BASE_ROOT="https://data-osdf.rda.ucar.edu/ncar/rda/d651027/cesmLE/CESM-CAM5-BGC-LE/ocn/proc/tseries/monthly"

mkdir -p "$OUTROOT"

# Fetch the directory index and extract ALL matching filenames for a var+member.
# Works whether the listing is HTML or plain text.
list_member_files () {
  local var="$1"   # TEMP | SALT | O2 | UVEL
  local mem="$2"   # 001..035 (zero-padded)
  local url="${BASE_ROOT}/${var}/"

  # get listing (follow redirects; quiet)
  local html
  html="$(curl -sL "$url" || true)"

  # Extract filenames like:
  # b.e11.BRCP85C5CNBDRD.f09_g16.001.pop.h.TEMP.200601-210012.nc
  # b.e11.BRCP85C5CNBDRD.f09_g16.001.pop.h.TEMP.200601-208012.nc
  # b.e11.BRCP85C5CNBDRD.f09_g16.001.pop.h.TEMP.208101-210012.nc
  #
  # Use a conservative regex: after ${var}. accept any non-quote chars up to ".nc"
  # (covers any number of splits / different span patterns)
  echo "$html" \
    | grep -oE "b\.e11\.BRCP85C5CNBDRD\.f09_g16\.${mem}\.pop\.h\.${var}\.[^\"]+\.nc" \
    | sort -u
}

# Download one file if not already present
grab_if_needed () {
  local url="$1"
  local dest="$2"
  if [[ -f "$dest" ]]; then
    echo "      [skip] exists: $(basename "$dest")"
    return 0
  fi
  echo "      [get]  $url"
  curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
}

echo "[info] Output root: $OUTROOT"
for var in "${VARS[@]}"; do
  OUTDIR="${OUTROOT}/${var}"
  INDEX_URL="${BASE_ROOT}/${var}/"
  mkdir -p "$OUTDIR"

  echo "============================"
  echo "[var] $var"
  echo "      Index: $INDEX_URL"
  echo "      Out:   $OUTDIR"

  # Optional manifest per variable
  MANIFEST="${OUTDIR}/manifest_${var}.txt"
  : > "$MANIFEST"

  for mem in $MEMBERS; do
    echo "  --- member ${mem} ---"
    files="$(list_member_files "$var" "$mem" || true)"

    if [[ -z "${files}" ]]; then
      echo "      [warn] no listing entries found for ${var}/${mem}"
      continue
    fi

    echo "      [list]"
    # Log & download each
    while IFS= read -r fname; do
      [[ -z "$fname" ]] && continue
      echo "        $fname"
      echo "$fname" >> "$MANIFEST"
      grab_if_needed "${INDEX_URL}${fname}" "${OUTDIR}/${fname}"
    done <<< "$files"
  done

  echo "      [done] Wrote manifest: $MANIFEST"
done

echo "[done] All variables and members processed."
