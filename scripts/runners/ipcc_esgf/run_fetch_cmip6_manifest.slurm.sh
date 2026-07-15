#!/bin/bash
#
# ==============================================================================
#  IPCC ESGF CMIP6 manifest fetch Slurm runner
#
#  This code was created by Isaac Brito-Morales
#  (ibrito@conservation.org)
#
#  Purpose:
#    - Run the R-based CMIP6 ESGF manifest fetcher as a long Slurm job
#    - Download selected files into the agreed /home/SB5/ipcc_esgf/downloads tree
#    - Keep the same environment-variable controls used by the interactive fetcher
#    - Avoid fragile interactive downloads for large model/variable batches
#
#  Intended to be run on Slurm-based HPC systems.
# ==============================================================================

#SBATCH -p grit_nodes
#SBATCH --job-name=ipcc_fetch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH -t 5-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ibrito@ucsb.edu
#SBATCH --output=/home/sandbox-sparc/cesmle-ocn-fetch/logs/ipcc_fetch_%j.out
#SBATCH --error=/home/sandbox-sparc/cesmle-ocn-fetch/logs/ipcc_fetch_%j.err
#SBATCH --chdir=/home/sandbox-sparc/cesmle-ocn-fetch

set -euo pipefail

mkdir -p /home/sandbox-sparc/cesmle-ocn-fetch/logs

MANIFEST="${MANIFEST:-data/manifests/ipcc_esgf_nci_cmip6_ocean_plus_siconc_wget_manifest.csv}"
OUT_ROOT="${OUT_ROOT:-/home/SB5/ipcc_esgf/downloads}"
DOWNLOAD="${DOWNLOAD:-yes}"
TIME_FILTER="${TIME_FILTER:-yes}"

echo "============================================================"
echo "Starting CMIP6 ESGF manifest fetch"
echo "MANIFEST    : ${MANIFEST}"
echo "OUT_ROOT    : ${OUT_ROOT}"
echo "MODELS      : ${MODELS:-<all>}"
echo "MEMBERS     : ${MEMBERS:-<all selected/first-realization rows>}"
echo "EXPERIMENTS : ${EXPERIMENTS:-<all>}"
echo "VARS        : ${VARS:-<all>}"
echo "TIME_FILTER : ${TIME_FILTER}"
echo "DOWNLOAD    : ${DOWNLOAD}"
echo "============================================================"

export MANIFEST
export OUT_ROOT
export DOWNLOAD
export TIME_FILTER

Rscript scripts/R/fetch_ipcc_esgf_cmip6_manifest.R

echo
echo "CMIP6 ESGF manifest fetch completed."
