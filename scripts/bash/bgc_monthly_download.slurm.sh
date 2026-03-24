#!/bin/bash
#
#SBATCH --job-name=bgc_monthly
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=6                  # parallel months
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/bgc_monthly_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/bgc_monthly_%j.err

set -euo pipefail

# Activate env so CLI is visible in batch
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
  source "$HOME/miniconda3/etc/profile.d/conda.sh"
  conda activate cmems || true
fi
export PATH="$HOME/.local/bin:$PATH"

# ========= Paths =========
REPO_ROOT="/home/sandbox-sparc/cesmle-ocn-fetch"
OUTROOT="${REPO_ROOT}/bgc_monthly_0p25"
LOGDIR="${REPO_ROOT}/logs"
mkdir -p "$OUTROOT" "$LOGDIR"

# ========= Dataset ID =========
DATASET_BGC_MONTHLY="cmems_mod_glo_bgc_my_0.25deg_P1M-m"

# ========= Time window (override at submit time) =========
YEAR_START="${YEAR_START:-1993}"
YEAR_END="${YEAR_END:-2025}"
MONTHS=(01 02 03 04 05 06 07 08 09 10 11 12)

# ========= Parallelism =========
CPUS="${SLURM_CPUS_PER_TASK:-6}"

# ========= Locate copernicusmarine CLI =========
CM="${CM:-$(command -v copernicusmarine || true)}"
if [[ -z "$CM" && -x "$HOME/.local/bin/copernicusmarine" ]]; then
  CM="$HOME/.local/bin/copernicusmarine"
fi
if [[ -z "$CM" ]]; then
  echo "[fatal] copernicusmarine CLI not found. Install/login first."
  exit 1
fi

echo "[info] Using CLI: $CM"
echo "[info] Output root: $OUTROOT"
echo "[info] Logs: $LOGDIR"
echo "[info] Parallel workers (months): $CPUS"

# ========= Build per-month tasks =========
TASKS="$(mktemp)"
: > "$TASKS"
trap 'rm -f "$TASKS"' EXIT

for year in $(seq "${YEAR_START}" "${YEAR_END}"); do
  for mm in "${MONTHS[@]}"; do
    OUTDIR="${OUTROOT}/${year}/${mm}"
    mkdir -p "$OUTDIR"

    # Monthly filename regex for that month
    # Kept broad enough to tolerate product-side naming details, but anchored on YYYYMM
    REGEX=".*${year}${mm}.*\\.nc"

    # quick completeness heuristic: monthly product should have at least one nc for the month
    existing=$(ls -1 "${OUTDIR}"/*.nc 2>/dev/null | wc -l || true)
    if (( existing >= 1 )); then
      echo "[skip] Likely complete (${year}-${mm}: ${existing} files) at ${OUTDIR}"
      continue
    fi

    echo "${DATASET_BGC_MONTHLY}|${REGEX}|${OUTDIR}" >> "$TASKS"
  done
done

# ========= Helper: tidy nested structure from older runs =========
tidy_nested_if_any() {
  local outdir="$1"

  if compgen -G "${outdir}/**/*.nc" > /dev/null 2>&1; then
    find "${outdir}" -mindepth 2 -type f -name "*.nc*" -print0 \
      | xargs -0 -I {} bash -c '
          src="{}"; base=$(basename "$src")
          mv -f "$src" "'"$outdir"'/"$base"
        ' || true
    find "${outdir}" -mindepth 1 -type d -empty -delete || true
  fi
}

# ========= Worker =========
fetch_month() {
  local dataset="$1"
  local regex="$2"
  local outdir="$3"

  echo "[get] dataset=${dataset}"
  echo "      regex=${regex}"
  echo "      outdir=${outdir}"

  # Flat layout: put files directly in $outdir
  "$CM" get \
    --dataset-id "$dataset" \
    --regex "$regex" \
    --output-directory "$outdir" \
    --no-directories

  # Tidy leftovers from earlier runs (if any)
  tidy_nested_if_any "$outdir"

  # Manifest
  local year mm manifest
  year=$(basename "$(dirname "$outdir")")
  mm=$(basename "$outdir")
  manifest="${outdir}/manifest_${year}${mm}.txt"
  ls -1 "${outdir}"/*.nc 2>/dev/null | sort > "$manifest" || true
  echo "[done] manifest: $manifest"
}

export -f fetch_month tidy_nested_if_any
export CM

# ========= Parallel execution =========
if [[ -s "$TASKS" ]]; then
  echo "============================"
  echo "[info] Starting downloads (parallel months = $CPUS)..."
  cat "$TASKS" | xargs -P "$CPUS" -n 1 -I {} bash -c '
    IFS="|" read -r dataset regex outdir <<< "{}"
    fetch_month "$dataset" "$regex" "$outdir"
  '
  echo "[info] All queued months processed."
else
  echo "[info] Nothing to download (tasks empty)."
fi

echo "[done] Check $OUTROOT"