MAXRUN=3

count_running () {
  squeue -u "$USER" -h -t R -n "regrid_*" | wc -l
}

for SCEN in hist rcp85; do
  for VAR in TEMP SALT O2 UVEL; do

    while [[ "$(count_running)" -ge "$MAXRUN" ]]; do
      echo "Already ${MAXRUN}+ regrid jobs running, waiting..."
      sleep 60
    done

    echo "Submitting job: SCEN=${SCEN} VAR=${VAR}"
    SCEN="${SCEN}" VAR="${VAR}" sbatch \
      --job-name="regrid_${SCEN}_${VAR}" \
      "${SCRIPT_DIR}/regrid_cesm_pop_1deg.slurm.sh"
  done
done