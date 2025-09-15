#!/bin/bash
#
#SBATCH --job-name=cesmle_list_par
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4          # <= parallel downloads = 4
#SBATCH --time=04:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=cesmle_list_par_%j.out
#SBATCH --error=cesmle_list_par_%j.err

set -euo pipefail

# ------------- CONFIG -------------
OUTROOT="/home/sandbox-sparc/z_esmLE_test"

# Default variables (override at submit time: --export=ALL,VARS="O2 UVEL")
VARS_DEFAULT=(TEMP SALT O2 UVEL)
VARS=(${VARS:-${VARS_DEFAULT[@]}})

BASE_ROOT="https://data-osdf.rda.ucar.edu/ncar/rda/d651027/cesmLE/CESM-CAM5-BGC-LE/ocn/proc/tseries/monthly"
CPUS="${SLURM_CPUS_PER_TASK:-4}"

# members 001–035
MEMBERS=$(seq -w 001 035)
MEM_RE='(00[1-9]|0[1-2][0-9]|03[0-5])'
DATE_RE='[0-9-]+'

# Fallback spans to probe when listing is empty/JS-driven
FALLBACK_SPANS=("200601-210012" "200601-208012" "208101-210012")

mkdir -p "$OUTROOT"

# ---------- helpers ----------
TASKS="$(mktemp)"; : > "$TASKS"
FAILED="$(mktemp)"; : > "$FAILED"
trap 'rm -f "$TASKS" "$FAILED"' EXIT

http_ok() {  # return 0 if URL -> HTTP 200 after redirects
  local url="$1"
  local code
  code=$(curl -s -o /dev/null -L -w "%{http_code}" "$url" || true)
  [[ "$code" == "200" ]]
}

# Robust, resumable downloader with verification + backoff
download_one() {
  url="$1"; dest="$2"; tmp="${dest}.part"
  max_tries="${MAX_TRIES:-6}"     # total attempts
  base_sleep="${BASE_SLEEP:-2}"   # seconds (for backoff)

  # expected size from server if provided
  want=$(curl -sIL "$url" | awk -F': ' 'tolower($1)=="content-length"{print $2}' | tr -d '\r')

  for try in $(seq 1 "$max_tries"); do
    # resume if partial exists
    if [[ -f "$tmp" ]]; then
      curl -fL --retry 0 -C - --connect-timeout 20 --max-time 0 -o "$tmp" "$url" || true
    else
      curl -fL --retry 0 -C - --connect-timeout 20 --max-time 0 -o "$tmp" "$url" || true
    fi

    have=""
    [[ -f "$tmp" ]] && have=$(stat -c%s "$tmp" 2>/dev/null || stat -f%z "$tmp")

    # success if size matches content-length
    if [[ -n "$want" && -n "$have" && "$want" == "$have" ]]; then
      mv -f "$tmp" "$dest"
      echo "[ok] $(basename "$dest")"
      return 0
    fi
    # or if server didn't give size but we got non-empty file
    if [[ -z "$want" && -s "$tmp" ]]; then
      mv -f "$tmp" "$dest"
      echo "[ok(no-CL)] $(basename "$dest")"
      return 0
    fi

    # exponential backoff with jitter (max ~30s)
    sleep_time=$(awk -v b="$base_sleep" -v t="$try" 'BEGIN{s=b*(2^(t-1)); if(s>30)s=30; print s}')
    jitter=$(awk 'BEGIN{srand(); printf "%.2f", rand()}' )
    sleep $(awk -v s="$sleep_time" -v j="$jitter" 'BEGIN{print s + j}')
  done

  echo "$url $dest" >> "$FAILED"
  echo "[fail] $(basename "$dest")"
  return 1
}
export -f download_one

echo "[info] Output root: $OUTROOT"
echo "[info] Vars: ${VARS[*]}"
echo "[info] Parallel workers: $CPUS"

for var in "${VARS[@]}"; do
  OUTDIR="${OUTROOT}/${var}"
  INDEX_URL="${BASE_ROOT}/${var}/"
  mkdir -p "$OUTDIR"

  echo "============================"
  echo "[var] $var"
  echo "      Index: $INDEX_URL"
  echo "      Out:   $OUTDIR"

  # Strict, var-specific regex to avoid unwanted siblings
  case "$var" in
    TEMP|SALT)
      REGEX="b\.e11\.BRCP85C5CNBDRD\.f09_g16\.${MEM_RE}\.pop\.h\.${var}\.${DATE_RE}\.nc"
      ;;
    UVEL)
      REGEX="b\.e11\.BRCP85C5CNBDRD\.f09_g16\.${MEM_RE}\.pop\.h\.UVEL\.${DATE_RE}\.nc"   # exclude UVEL2
      ;;
    O2)
      REGEX="b\.e11\.BRCP85C5CNBDRD\.f09_g16\.${MEM_RE}\.pop\.h\.O2\.${DATE_RE}\.nc"     # exclude O2SAT, O2_CONSUMPTION, etc.
      ;;
    *)
      echo "      [warn] unknown var ${var}; skipping."; continue;;
  esac

  # Try to scrape a directory listing (may be empty if page is JS-driven)
  html="$(curl -sL "$INDEX_URL" || true)"
  mapfile -t files < <(echo "$html" | grep -oE "$REGEX" | sort -u)

  MANIFEST="${OUTDIR}/manifest_${var}.txt"
  : > "$MANIFEST"

  if [[ "${#files[@]}" -gt 0 ]]; then
    echo "      [list] ${#files[@]} from listing"
    for fname in "${files[@]}"; do
      echo "        $fname" | tee -a "$MANIFEST" >/dev/null
      url="${INDEX_URL}${fname}"
      dest="${OUTDIR}/${fname}"
      if [[ -f "$dest" ]]; then
        echo "      [skip] exists: $fname"
        continue
      fi
      echo "$url $dest" >> "$TASKS"
    done
    echo "      [done] manifest: $MANIFEST"
  else
    # Fallback: probe known spans for every member
    echo "      [info] no list entries; probing known spans…"
    for mem in $MEMBERS; do
      for span in "${FALLBACK_SPANS[@]}"; do
        fname="b.e11.BRCP85C5CNBDRD.f09_g16.${mem}.pop.h.${var}.${span}.nc"
        url="${INDEX_URL}${fname}"
        dest="${OUTDIR}/${fname}"
        if [[ -f "$dest" ]]; then
          echo "      [skip] exists: $fname"
          continue
        fi
        if http_ok "$url"; then
          echo "        $fname" | tee -a "$MANIFEST" >/dev/null
          echo "$url $dest" >> "$TASKS"
        fi
      done
    done
    echo "      [done] manifest: $MANIFEST"
  fi
done

# -------- parallel downloads --------
if [[ -s "$TASKS" ]]; then
  echo "============================"
  echo "[info] Starting parallel downloads (P=$CPUS)…"
  xargs -P "$CPUS" -n 2 bash -c 'download_one "$0" "$1"' < "$TASKS" || true
  echo "[info] First pass complete."

  if [[ -s "$FAILED" ]]; then
    echo "[info] Retrying failures sequentially…"
    while read -r url dest; do
      bash -c 'download_one "$0" "$1"' "$url" "$dest" || true
    done < "$FAILED"
  fi
else
  echo "[info] Nothing to download."
fi

echo "[done] Check $OUTROOT"

#sbatch --export=ALL,VARS="O2 UVEL" download_cesmle_list_par_robust.slurm
