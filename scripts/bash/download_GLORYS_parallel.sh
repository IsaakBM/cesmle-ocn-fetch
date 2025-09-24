#!/bin/bash
#
#SBATCH --job-name=glorys12v1_daily
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys12v1_daily_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys12v1_daily_%j.err

set -euo pipefail

# ========= Output root =========
OUTROOT="/home/sandbox-sparc/cesmle-ocn-fetch/glorys12v1"

# ========= Download config =========
CPUS="${SLURM_CPUS_PER_TASK:-4}"

PRODUCT="GLOBAL_MULTIYEAR_PHY_001_030"
SUBDATASET="${SUBDATASET:-cmems_mod_glo_phy_my_0.083deg_P1D-m_202311}"
BASE_LIST_ROOT="https://data.marine.copernicus.eu/product/${PRODUCT}/files"

YEAR_START="${YEAR_START:-1993}"
YEAR_END="${YEAR_END:-2021}"
MONTHS=(01 02 03 04 05 06 07 08 09 10 11 12)

# Optional: filter filenames by date (regex, e.g., '^199801')
DATE_FILTER_REGEX="${DATE_FILTER_REGEX:-}"

# Optional Copernicus cookie jar for auth
COP_COOKIE="${COP_COOKIE:-}"  # e.g., /home/ibrito/.cookies/cmems.txt

mkdir -p "$OUTROOT"

# ---------- helpers ----------
TASKS="$(mktemp)"; : > "$TASKS"
FAILED="$(mktemp)"; : > "$FAILED"
trap 'rm -f "$TASKS" "$FAILED"' EXIT

curl_base_args=(-fL --retry 0 --connect-timeout 20 --max-time 0)
if [[ -n "${COP_COOKIE}" ]]; then
  curl_base_args=(-fL --retry 0 --connect-timeout 20 --max-time 0 -b "$COP_COOKIE" -c "$COP_COOKIE")
fi

http_ok() {  # return 0 if URL -> HTTP 200
  local url="$1"
  local code
  if [[ -n "${COP_COOKIE}" ]]; then
    code=$(curl -s -o /dev/null -L -w "%{http_code}" -b "$COP_COOKIE" -c "$COP_COOKIE" "$url" || true)
  else
    code=$(curl -s -o /dev/null -L -w "%{http_code}" "$url" || true)
  fi
  [[ "$code" == "200" ]]
}

# Robust, resumable downloader
download_one() {
  local url_a="$1"        # primary (query-style)
  local url_b="$2"        # fallback (direct-folder)
  local dest="$3"
  local tmp="${dest}.part"
  local max_tries="${MAX_TRIES:-6}"
  local base_sleep="${BASE_SLEEP:-2}"

  local url="$url_a"
  if ! http_ok "$url"; then
    if http_ok "$url_b"; then
      url="$url_b"
    fi
  fi

  local want
  if [[ -n "${COP_COOKIE}" ]]; then
    want=$(curl -sIL ${curl_base_args[@]:1} "$url" | awk -F': ' 'tolower($1)=="content-length"{print $2}' | tr -d '\r' || true)
  else
    want=$(curl -sIL "$url" | awk -F': ' 'tolower($1)=="content-length"{print $2}' | tr -d '\r' || true)
  fi

  for try in $(seq 1 "$max_tries"); do
    curl "${curl_base_args[@]}" -C - -o "$tmp" "$url" || true

    local have=""
    [[ -f "$tmp" ]] && have=$(stat -c%s "$tmp" 2>/dev/null || stat -f%z "$tmp")

    if [[ -n "$want" && -n "$have" && "$want" == "$have" ]]; then
      mv -f "$tmp" "$dest"
      echo "[ok] $(basename "$dest")"
      return 0
    fi
    if [[ -z "$want" && -s "$tmp" ]]; then
      mv -f "$tmp" "$dest"
      echo "[ok(no-CL)] $(basename "$dest")"
      return 0
    fi

    sleep_time=$(awk -v b="$base_sleep" -v t="$try" 'BEGIN{s=b*(2^(t-1)); if(s>30)s=30; print s}')
    jitter=$(awk 'BEGIN{srand(); printf "%.2f", rand()}' )
    sleep $(awk -v s="$sleep_time" -v j="$jitter" 'BEGIN{print s + j}')
  done

  echo "$url_a $url_b $dest" >> "$FAILED"
  echo "[fail] $(basename "$dest")"
  return 1
}
export -f download_one
export COP_COOKIE
export -f http_ok

echo "[info] Output root: $OUTROOT"
echo "[info] Parallel workers: $CPUS"

FNAME_RE='mercatorglorys12v1_gl12_mean_[0-9]{8}_R[0-9]{8}\.nc'

# -------- build task list --------
for year in $(seq "${YEAR_START}" "${YEAR_END}"); do
  for mm in "${MONTHS[@]}"; do
    OUTDIR="${OUTROOT}/${year}/${mm}"
    mkdir -p "$OUTDIR"

    LIST_URL="${BASE_LIST_ROOT}?subdataset=${SUBDATASET}/${year}/${mm}/"
    DL_PREFIX_A="${BASE_LIST_ROOT}?subdataset=${SUBDATASET}/${year}/${mm}/"
    DL_PREFIX_B="https://data.marine.copernicus.eu/products/${PRODUCT}/files/${SUBDATASET}/${year}/${mm}/"

    echo "============================"
    echo "[list] ${year}/${mm}"
    echo "      ${LIST_URL}"

    if [[ -n "${COP_COOKIE}" ]]; then
      html="$(curl -sL -b "$COP_COOKIE" -c "$COP_COOKIE" "$LIST_URL" || true)"
    else
      html="$(curl -sL "$LIST_URL" || true)"
    fi

    mapfile -t files < <(echo "$html" | grep -oE "$FNAME_RE" | sort -u)

    if [[ -n "$DATE_FILTER_REGEX" && "${#files[@]}" -gt 0 ]]; then
      mapfile -t files < <(printf "%s\n" "${files[@]}" | grep -E "$DATE_FILTER_REGEX" | sort -u || true)
    fi

    if [[ "${#files[@]}" -gt 0 ]]; then
      echo "      [list] ${#files[@]} files"
      for fname in "${files[@]}"; do
        dest="${OUTDIR}/${fname}"
        if [[ -f "$dest" ]]; then
          echo "      [skip] exists: $fname"
          continue
        fi
        url_a="${DL_PREFIX_A}${fname}"
        url_b="${DL_PREFIX_B}${fname}"
        echo "$url_a $url_b $dest" >> "$TASKS"
      done
    else
      echo "      [warn] no files found in listing"
    fi
  done
done

# -------- parallel downloads --------
if [[ -s "$TASKS" ]]; then
  echo "============================"
  echo "[info] Starting parallel downloads (P=$CPUS)…"
  xargs -P "$CPUS" -n 3 bash -c 'download_one "$0" "$1" "$2"' < "$TASKS" || true
  echo "[info] First pass complete."

  if [[ -s "$FAILED" ]]; then
    echo "[info] Retrying failures sequentially…"
    while read -r url_a url_b dest; do
      bash -c 'download_one "$0" "$1" "$2"' "$url_a" "$url_b" "$dest" || true
    done < "$FAILED"
  fi
else
  echo "[info] Nothing to download."
fi

echo "[done] Check $OUTROOT"