#!/bin/bash
#
#SBATCH --job-name=glorys12v1_daily
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=6                  # parallel months
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys12v1_daily_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys12v1_daily_%j.err

set -euo pipefail

# ========= Paths =========
REPO_ROOT="/home/sandbox-sparc/cesmle-ocn-fetch"
OUTROOT="${REPO_ROOT}/glorys12v1"
LOGDIR="${REPO_ROOT}/logs"
mkdir -p "$OUTROOT" "$LOGDIR"

# ========= Dataset IDs (original files) =========
DATASET_MY="cmems_mod_glo_phy_my_0.083deg_P1D-m_202311"      # 1993–2020
DATASET_MYINT="cmems_mod_glo_phy_myint_0.083deg_P1D-m_202311" # 2021+

# ========= Time window (edit via env if needed) =========
YEAR_START="${YEAR_START:-1993}"
YEAR_END="${YEAR_END:-2021}"
MONTHS=(01 02 03 04 05 06 07 08 09 10 11 12)

# ========= Parallelism =========
CPUS="${SLURM_CPUS_PER_TASK:-4}"

# ========= Locate copernicus-marine CLI =========
CM="${CM:-$(command -v copernicus-marine || true)}"
if [[ -z "$CM" && -x "$HOME/.local/bin/copernicus-marine" ]]; then
  CM="$HOME/.local/bin/copernicus-marine"
fi
if [[ -z "$CM" ]]; then
  echo "[fatal] copernicus-marine CLI not found in PATH or ~/.local/bin"
  echo "        Install with:  pip install --user copernicus-marine-client"
  echo "        Then run:      ~/.local/bin/copernicus-marine login"
  exit 1
fi

echo "[info] Using CLI: $CM"
echo "[info] Output root: $OUTROOT"
echo "[info] Logs: $LOGDIR"
echo "[info] Parallel workers (months): $CPUS"

# ========= Build per-month tasks =========
TASKS="$(mktemp)"; : > "$TASKS"
trap 'rm -f "$TASKS"' EXIT

for year in $(seq "${YEAR_START}" "${YEAR_END}"); do
  for mm in "${MONTHS[@]}"; do
    if (( year < 1993 )); then continue; fi
    if (( year == 2021 )); then
      DATASET="$DATASET_MYINT"
    elif (( year <= 2020 )); then
      DATASET="$DATASET_MY"
    else
      continue
    fi

    OUTDIR="${OUTROOT}/${year}/${mm}"
    mkdir -p "$OUTDIR"

    REGEX="mercatorglorys12v1_gl12_mean_${year}${mm}[0-9]{2}_R[0-9]{8}\\.nc"

    existing=$(ls -1 "${OUTDIR}"/mercatorglorys12v1_gl12_mean_${year}${mm}??_R????????.nc 2>/dev/null | wc -l || true)
    if (( existing >= 28 )); then
      echo "[skip] Likely complete (${year}-${mm} has ${existing} files): ${OUTDIR}"
      continue
    fi

    echo "${DATASET}|${REGEX}|${OUTDIR}" >> "$TASKS"
  done
done

# ========= Worker =========
fetch_month() {
  local dataset="$1"
  local regex="$2"
  local outdir="$3"

  echo "[get] dataset=${dataset}"
  echo "      regex=${regex}"
  echo "      outdir=${outdir}"

  "$CM" get \
    --dataset-id "$dataset" \
    --regex "$regex" \
    --output-path "$outdir" \
    --no-confirmation \
    --force-download

  year=$(basename "$(dirname "$outdir")")
  mm=$(basename "$outdir")
  manifest="${outdir}/manifest_${year}${mm}.txt"
  ls -1 "${outdir}"/mercatorglorys12v1_gl12_mean_${year}${mm}??_R????????.nc 2>/dev/null | sort > "$manifest" || true
  echo "[done] manifest: $manifest"
}

export -f fetch_month
export CM

# ========= Parallel execution =========
if [[ -s "$TASKS" ]]; then
  echo "============================"
  echo "[info] Starting downloads (parallel months = $CPUS)…"
  cat "$TASKS" | xargs -P "$CPUS" -n 1 -I {} bash -c '
    IFS="|" read -r dataset regex outdir <<< "{}"
    fetch_month "$dataset" "$regex" "$outdir"
  '
  echo "[info] All queued months processed."
else
  echo "[info] Nothing to download (tasks empty)."
fi

echo "[done] Check $OUTROOT"