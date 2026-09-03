#!/usr/bin/env bash
# ==============================================================================
#  Assess SB5 storage migration state
#
#  Ownership:
#    This code was created by Isaac Brito-Morales
#    (ibrito@conservation.org)
#
#  Purpose:
#    Produce a read-only report comparing the legacy /home/SB5 roots with the
#    agreed target storage layout before deciding whether to archive legacy
#    paths or keep compatibility aliases.
#
#  Notes:
#    - This script does not move, delete, rename, copy, or symlink data.
#    - It is intended to run on the cluster where /home/SB5 is mounted.
# ==============================================================================

set -euo pipefail

SB5_ROOT="${SB5_ROOT:-/home/SB5}"
REPORT_DIR="${REPORT_DIR:-/tmp/sb5_storage_migration_assessment_$(date +%Y%m%d_%H%M%S)}"
MAX_DEPTH="${MAX_DEPTH:-4}"
SAMPLE_LIMIT="${SAMPLE_LIMIT:-8}"

mkdir -p "${REPORT_DIR}"

MIGRATION_MAP="${REPORT_DIR}/migration_map.tsv"
SUMMARY_FILE="${REPORT_DIR}/summary.tsv"
DIR_COUNTS_FILE="${REPORT_DIR}/top_level_dir_counts.tsv"
SAMPLE_FILE="${REPORT_DIR}/sample_files.txt"
DRY_RUN_FILE="${REPORT_DIR}/dry_run_compatibility_actions.sh"

cat > "${MIGRATION_MAP}" <<EOF
legacy_root	target_root	status
${SB5_ROOT}/glorys12v1_monthly_0p05	${SB5_ROOT}/reanalysis/glorys12v1/monthly_0p05	verify_then_keep_legacy_alias
${SB5_ROOT}/global_ocean_biogeochemistry_hindcast_monthly_0p25	${SB5_ROOT}/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25	verify_then_keep_legacy_alias
${SB5_ROOT}/global_ocean_biogeochemistry_hindcast_monthly_0p05	${SB5_ROOT}/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05	verify_then_keep_legacy_alias
${SB5_ROOT}/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast	${SB5_ROOT}/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast	verify_then_keep_legacy_alias
${SB5_ROOT}/ipcc_esgf_downloads	${SB5_ROOT}/ipcc_esgf/downloads	verify_then_keep_legacy_alias
${SB5_ROOT}/ipcc_esgf_monthly_1deg	${SB5_ROOT}/ipcc_esgf/monthly_1deg	verify_then_keep_legacy_alias
${SB5_ROOT}/rcp85	${SB5_ROOT}/ipcc_esgf/cmip5_rcp85	verify_then_keep_legacy_alias
EOF

echo "Writing read-only SB5 migration assessment to: ${REPORT_DIR}"

{
  echo "host: $(hostname)"
  echo "date: $(date)"
  echo "sb5_root: ${SB5_ROOT}"
  echo "max_depth: ${MAX_DEPTH}"
  echo "sample_limit: ${SAMPLE_LIMIT}"
} > "${REPORT_DIR}/run_context.txt"

{
  printf 'legacy_root\ttarget_root\tlegacy_exists\ttarget_exists\tlegacy_size\ttarget_size\tlegacy_files_maxdepth%s\ttarget_files_maxdepth%s\tlegacy_inode\ttarget_inode\tstatus\n' \
    "${MAX_DEPTH}" "${MAX_DEPTH}"

  tail -n +2 "${MIGRATION_MAP}" | while IFS=$'\t' read -r legacy target status; do
    legacy_exists="no"
    target_exists="no"
    legacy_size="NA"
    target_size="NA"
    legacy_files="NA"
    target_files="NA"
    legacy_inode="NA"
    target_inode="NA"

    if [[ -e "${legacy}" ]]; then
      legacy_exists="yes"
      legacy_size="$(du -sh "${legacy}" 2>/dev/null | awk '{print $1}')"
      legacy_files="$(find "${legacy}" -maxdepth "${MAX_DEPTH}" -type f 2>/dev/null | wc -l | tr -d ' ')"
      legacy_inode="$(stat -c '%d:%i' "${legacy}" 2>/dev/null || stat -f '%d:%i' "${legacy}" 2>/dev/null || true)"
    fi

    if [[ -e "${target}" ]]; then
      target_exists="yes"
      target_size="$(du -sh "${target}" 2>/dev/null | awk '{print $1}')"
      target_files="$(find "${target}" -maxdepth "${MAX_DEPTH}" -type f 2>/dev/null | wc -l | tr -d ' ')"
      target_inode="$(stat -c '%d:%i' "${target}" 2>/dev/null || stat -f '%d:%i' "${target}" 2>/dev/null || true)"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${legacy}" "${target}" "${legacy_exists}" "${target_exists}" \
      "${legacy_size}" "${target_size}" "${legacy_files}" "${target_files}" \
      "${legacy_inode}" "${target_inode}" "${status}"
  done
} > "${SUMMARY_FILE}"

{
  printf 'root\tchild\tfiles_maxdepth3\n'
  tail -n +2 "${MIGRATION_MAP}" | while IFS=$'\t' read -r legacy target _status; do
    for root in "${legacy}" "${target}"; do
      [[ -d "${root}" ]] || continue
      find "${root}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | while read -r child; do
        printf '%s\t%s\t%s\n' \
          "${root}" \
          "$(basename "${child}")" \
          "$(find "${child}" -maxdepth 3 -type f 2>/dev/null | wc -l | tr -d ' ')"
      done
    done
  done
} > "${DIR_COUNTS_FILE}"

{
  tail -n +2 "${MIGRATION_MAP}" | while IFS=$'\t' read -r legacy target _status; do
    for root in "${legacy}" "${target}"; do
      echo
      echo "### ${root}"
      if [[ -d "${root}" ]]; then
        find "${root}" -maxdepth "${MAX_DEPTH}" -type f 2>/dev/null | head -n "${SAMPLE_LIMIT}"
      else
        echo "MISSING"
      fi
    done
  done
} > "${SAMPLE_FILE}"

{
  echo "#!/usr/bin/env bash"
  echo "# Dry-run compatibility actions only. Review manually before any real action."
  echo "# These commands are intentionally commented out."
  echo
  tail -n +2 "${MIGRATION_MAP}" | while IFS=$'\t' read -r legacy target _status; do
    echo "# Legacy path: ${legacy}"
    echo "# Target path: ${target}"
    echo "# After downstream tests pass, choose one policy:"
    echo "#   keep: leave both roots untouched for compatibility"
    echo "#   alias: replace the legacy path with a symlink to the target path"
    echo "#   archive: rename legacy path under an archive namespace"
    echo "# Example alias commands, not executed:"
    echo "# mv '${legacy}' '${legacy}.legacy_$(date +%Y%m%d)'"
    echo "# ln -s '${target}' '${legacy}'"
    echo
  done
} > "${DRY_RUN_FILE}"
chmod +x "${DRY_RUN_FILE}"

find "${SB5_ROOT}" -maxdepth 5 -type l -ls 2>/dev/null > "${REPORT_DIR}/symlinks.txt"
ls -lah "${SB5_ROOT}" > "${REPORT_DIR}/top_level_listing.txt"

echo
echo "Done."
echo "Report directory: ${REPORT_DIR}"
echo
echo "Paste this summary first:"
cat "${SUMMARY_FILE}"
echo
echo "Other useful files:"
echo "  ${DIR_COUNTS_FILE}"
echo "  ${SAMPLE_FILE}"
echo "  ${DRY_RUN_FILE}"
