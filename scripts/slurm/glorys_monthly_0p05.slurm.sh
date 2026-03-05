#!/bin/bash
#
# ==============================================================================
#  GLORYS12v1 monthly baseline builder + regrid to 0.05° (2006–2014)
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Build monthly means from daily GLORYS12v1 files (2006–2014)
#    - Select one variable at a time (VAR)
#    - Regrid monthly means to a uniform 0.05° lon/lat grid using remapbil
#    - Restartable, safe tmp handling
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=glorys_monmean_0p05
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH -t 2-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/glorys_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail

# ==============================================================================
# Required env var (passed at sbatch time)
#   VAR: thetao | so | mlotst | uo | vo | zos | bottomT
# ==============================================================================
VAR="${VAR:-}"
if [[ -z "$VAR" ]]; then
  echo "ERROR: VAR must be set"
  echo "Example: VAR=thetao sbatch glorys_monthly_0p05.slurm.sh"
  exit 1
fi

# ==============================================================================
# Paths
# ==============================================================================
INROOT="/home/sandbox-sparc/cesmle-ocn-fetch/glorys12v1"
OUTROOT="/home/SB5/glorys12v1_monthly_0p05"
OUTDIR="${OUTROOT}/${VAR}"
PARTS="${OUTDIR}/parts"
mkdir -p "$PARTS"

LOGDIR="/home/sandbox-sparc/cesmle-ocn-fetch/logs"
mkdir -p "$LOGDIR"

# ==============================================================================
# Temp directory
# ==============================================================================
TMPBASE="${SLURM_TMPDIR:-${OUTROOT}/tmp}"
TMPDIR="${TMPBASE}/glorys_${VAR}"
mkdir -p "$TMPDIR"

# Free-space preflight
MIN_FREE_GB=40
FREE_GB=$(df -BG "$TMPBASE" | awk 'NR==2 {gsub("G","",$4); print $4}')
if [[ -z "$FREE_GB" ]]; then
  echo "ERROR: Could not determine free space on: $TMPBASE"
  exit 1
fi
if [[ "$FREE_GB" -lt "$MIN_FREE_GB" ]]; then
  echo "ERROR: Low free space where TMP lives: ${FREE_GB}G free, need at least ${MIN_FREE_GB}G."
  echo "       Path checked: $TMPBASE"
  exit 1
fi

# ==============================================================================
# Target 0.05° grid (match GLORYS latitude extent: -80..90)
# ==============================================================================
GRIDFILE="${OUTROOT}/grid_0p05_glorys_lat80_90.txt"
if [[ ! -s "$GRIDFILE" ]]; then
  cat > "$GRIDFILE" << 'EOF'
gridtype = lonlat
xsize    = 7200
ysize    = 3401
xfirst   = -180.0
xinc     = 0.05
yfirst   = -80.0
yinc     = 0.05
EOF
fi

METHOD="remapbil"

echo "================================================="
echo " GLORYS input   : $INROOT"
echo " Variable       : $VAR"
echo " Years          : 2006–2014"
echo " Output dir     : $OUTDIR"
echo " Temp dir       : $TMPDIR"
echo " Grid           : $GRIDFILE (0.05°, remapbil)"
echo " CPUs           : ${SLURM_CPUS_PER_TASK:-4}"
echo " Free tmp fs    : ${FREE_GB}G (min ${MIN_FREE_GB}G)"
echo "================================================="

if [[ ! -d "$INROOT" ]]; then
  echo "ERROR: Input directory not found: $INROOT"
  exit 1
fi

# ==============================================================================
# Build one month
# ==============================================================================
process_month() {
  local yyyy="$1"
  local mm="$2"

  local inpath="${INROOT}/${yyyy}/${mm}"
  local out="${PARTS}/glorys12v1_${VAR}_${yyyy}${mm}.monmean.0p05.nc"

  if [[ -s "$out" ]]; then
    echo "SKIP (exists): $out"
    return 0
  fi

  if [[ ! -d "$inpath" ]]; then
    echo "WARN: Missing directory: $inpath"
    return 0
  fi

  # Collect daily files (sorted)
  mapfile -t files < <(find "$inpath" -maxdepth 1 -type f -name "*.nc*" | sort)
  if [[ "${#files[@]}" -eq 0 ]]; then
    echo "WARN: No files found: $inpath"
    return 0
  fi

  local base="glorys_${VAR}_${yyyy}${mm}"
  local tmp_merge="${TMPDIR}/.${base}.merge.nc"
  local tmp_mon="${TMPDIR}/.${base}.monmean.nc"
  local tmp_out="${TMPDIR}/.${base}.out.nc"

  # Ensure cleanup on failure
  trap 'rm -f "$tmp_merge" "$tmp_mon" "$tmp_out"' RETURN

  # 1) merge daily files in this month, select VAR to reduce size
  /usr/bin/cdo -L -O -P 1 -selname,"${VAR}" -mergetime "${files[@]}" "$tmp_merge"

  # 2) monthly mean (series is within one month, so output is one timestep)
  /usr/bin/cdo -L -O -P 1 monmean "$tmp_merge" "$tmp_mon"

  # 3) regrid to 0.05°
  /usr/bin/cdo -L -O -P 1 ${METHOD},"${GRIDFILE}" "$tmp_mon" "$tmp_out"

  mv "$tmp_out" "$out"

  trap - RETURN
  echo "DONE: $out"
}

# ==============================================================================
# Main loop: 2006–2014, months 01–12
# ==============================================================================
for yyyy in $(seq 2006 2014); do
  for mm in 01 02 03 04 05 06 07 08 09 10 11 12; do
    process_month "$yyyy" "$mm"
  done
done

echo "All done: ${VAR} (2006–2014 monthly means at 0.05°)"