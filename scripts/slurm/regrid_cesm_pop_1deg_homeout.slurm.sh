#!/bin/bash
#
# ==============================================================================
#  CESM POP regridding pipeline (1-degree global grid)
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@eri.ucsb.edu)
#
#  Please do not distribute or reuse without permission.
#  NO GUARANTEES THAT THIS CODE IS CORRECT.
#  Use at your own risk. Caveat emptor.
#
#  Purpose:
#    - Regrid CESM POP ocean variables (TEMP, SALT, O2, UVEL)
#      to a regular 1° global grid (360x180)
#    - Process files independently (safe, restartable)
#    - Optionally merge RCP85 time chunks per ensemble member
#
#  Intended to be run on Slurm-based HPC systems.
#
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=cesm_regrid
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=5
#SBATCH --mem=128G
#SBATCH -t 3-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@eri.ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/regrid_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/regrid_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail

# ==============================================================================
# Required environment variables (passed at sbatch time)
#   SCEN: hist | rcp85
#   VAR : TEMP | SALT | O2 | UVEL
# ==============================================================================

SCEN="${SCEN:-}"
VAR="${VAR:-}"

if [[ -z "$SCEN" || -z "$VAR" ]]; then
  echo "ERROR: SCEN and VAR must be set"
  echo "Example: SCEN=hist VAR=TEMP sbatch regrid_cesm_pop_1deg.slurm.sh"
  exit 1
fi

if [[ "$SCEN" != "hist" && "$SCEN" != "rcp85" ]]; then
  echo "ERROR: SCEN must be 'hist' or 'rcp85'"
  exit 1
fi

# ==============================================================================
# Paths
# ==============================================================================
INROOT="/home/sandbox-sparc/cesmle-ocn-fetch/cesm"
INPATH="${INROOT}/${SCEN}/${VAR}"

# Outputs go to home (big filesystem)
HOME_OUTROOT="/home/sandbox-sparc/z_cesm_test/cesm_regrid_1deg"
OUTDIR="${HOME_OUTROOT}/${SCEN}/${VAR}"
PARTS="${OUTDIR}/parts"
MERGED="${OUTDIR}/merged"

mkdir -p "$PARTS" "$MERGED"

# Temp goes to scratch (fast, limited space)
SCRATCH_ROOT="/scratch/sparc"
USER_SCRATCH="${SCRATCH_ROOT}/${USER}"

if [[ ! -d "$SCRATCH_ROOT" ]]; then
  echo "ERROR: Scratch root not found: $SCRATCH_ROOT"
  exit 1
fi

mkdir -p "${USER_SCRATCH}"

TMPROOT="${USER_SCRATCH}/cesm_regrid_1deg_tmp"
TMPDIR="${TMPROOT}/${SCEN}/${VAR}"
mkdir -p "$TMPDIR"

# ==============================================================================
# Scratch free-space preflight (scratch is only ~133G total)
# ==============================================================================
MIN_FREE_GB=60
FREE_GB=$(df -BG "$SCRATCH_ROOT" | awk 'NR==2 {gsub("G","",$4); print $4}')

if [[ -z "$FREE_GB" ]]; then
  echo "ERROR: Could not determine free space on: $SCRATCH_ROOT"
  exit 1
fi

if [[ "$FREE_GB" -lt "$MIN_FREE_GB" ]]; then
  echo "ERROR: Low free space on scratch: ${FREE_GB}G free, need at least ${MIN_FREE_GB}G."
  echo "       Path checked: $SCRATCH_ROOT"
  exit 1
fi

echo "================================================="
echo " Scenario      : $SCEN"
echo " Variable      : $VAR"
echo " Input path    : $INPATH"
echo " Output dir    : $OUTDIR"
echo " Temp dir      : $TMPDIR"
echo " CPUs          : ${SLURM_CPUS_PER_TASK:-8}"
echo " Free scratch  : ${FREE_GB}G (min ${MIN_FREE_GB}G)"
echo "================================================="

if [[ ! -d "$INPATH" ]]; then
  echo "ERROR: Input directory not found: $INPATH"
  exit 1
fi

# ==============================================================================
# Performance safety (avoid nested parallelism)
# ==============================================================================
# Keep this conservative because tmp files are huge and scratch is small.
NPROC=2

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

GRID="r360x180"
METHOD="remapbil"

# ==============================================================================
# Select input files
# ==============================================================================
declare -a FILES

if [[ "$SCEN" == "hist" ]]; then
  mapfile -t FILES < <(
    find "$INPATH" -type f -name "*.nc*" \
    | grep "192001-200512" \
    | sort
  )
else
  mapfile -t FILES < <(
    find "$INPATH" -type f -name "*.nc*" \
    | egrep "200601-208012|208101-210012|200601-210012" \
    | sort
  )
fi

if [[ "${#FILES[@]}" -eq 0 ]]; then
  echo "ERROR: No matching input files found"
  exit 1
fi

echo "Found ${#FILES[@]} files to regrid."

# ==============================================================================
# Regrid worker
# ==============================================================================
regrid_one() {
  local in="$1"
  local base out tmp

  base="$(basename "$in")"

  # Ensure clean base name (avoid .1deg.1deg.nc)
  base="${base%.nc.part}"
  base="${base%.nc}"

  out="${PARTS}/${base}.1deg.nc"
  if [[ -s "$out" ]]; then
    echo "SKIP (exists): $out"
    return 0
  fi

  # Unique tmp per file, on scratch
  tmp="${TMPDIR}/.${base}.tmp.nc"

  # Clean up tmp if anything fails mid-write
  trap 'rm -f "$tmp"' RETURN

  # -L helps avoid NetCDF4/HDF5 crashes with non-thread-safe libs
  cdo -L -O -P 1 ${METHOD},${GRID} -selname,${VAR} "$in" "$tmp"

  # Move final file to home output (cross-FS move = copy+delete, but OK)
  mv "$tmp" "$out"

  # Clear trap and report
  trap - RETURN
  echo "DONE: $out"
}

export -f regrid_one
export PARTS TMPDIR GRID METHOD VAR

# ==============================================================================
# Stage 1: parallel regridding
# ==============================================================================
printf "%s\n" "${FILES[@]}" \
  | xargs -I{} -P "$NPROC" bash -c 'regrid_one "$@"' _ {}

echo "Stage 1 complete: regridding finished."

# ==============================================================================
# Stage 2: merge per ensemble member (RCP85 only)
# ==============================================================================
if [[ "$SCEN" == "rcp85" ]]; then
  echo "Stage 2: merging per ensemble member (RCP85)"

  shopt -s nullglob

  # Copy already-merged members (2006–2100)
  for f in "${PARTS}"/*"${VAR}".200601-210012*.1deg.nc; do
    base="$(basename "$f")"
    out="${MERGED}/${base}"
    [[ -s "$out" ]] || cp -p "$f" "$out"
  done

  # Merge split members
  for f1 in "${PARTS}"/*"${VAR}".200601-208012*.1deg.nc; do
    base1="$(basename "$f1")"
    member="$(echo "$base1" | sed -n 's/.*f09_g16\.\([0-9]\{3\}\)\.pop.*/\1/p')"
    [[ -z "$member" ]] && continue

    f2=( "${PARTS}"/*"f09_g16.${member}.pop.h.${VAR}.208101-210012"*.1deg.nc )
    [[ "${#f2[@]}" -eq 0 ]] && continue

    outbase="$(echo "$base1" | sed 's/200601-208012/200601-210012/')"
    out="${MERGED}/${outbase}"

    [[ -s "$out" ]] && continue

    cdo -L -O -P 1 mergetime "$f1" "${f2[0]}" "$out"
    echo "MERGED member ${member}: $out"
  done

  echo "Stage 2 complete: merging finished."
fi

echo "All done: ${SCEN}/${VAR}"