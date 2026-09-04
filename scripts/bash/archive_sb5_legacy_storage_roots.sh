#!/usr/bin/env bash
# ==============================================================================
#  Archive SB5 legacy storage roots
#
#  Ownership:
#    This code was created by Isaac Brito-Morales
#    (ibrito@conservation.org)
#
#  Purpose:
#    Archive old top-level /home/SB5 storage roots after the migrated target
#    roots have been verified, then leave compatibility symlinks at the old
#    paths so older notebooks/scripts can still resolve.
#
#  Notes:
#    - Dry-run is the default.
#    - This script never deletes data.
#    - It intentionally does not touch /home/SB5/downscaled or
#      /home/SB5/ocean_downscaling_products*.
# ==============================================================================

set -euo pipefail

SB5_ROOT="${SB5_ROOT:-/home/SB5}"
ARCHIVE_TAG="${ARCHIVE_TAG:-$(date +%Y%m%d)}"
ARCHIVE_ROOT="${ARCHIVE_ROOT:-${SB5_ROOT}/archive/storage_roots_${ARCHIVE_TAG}}"
DRY_RUN="${DRY_RUN:-yes}"
CREATE_SYMLINKS="${CREATE_SYMLINKS:-yes}"

case "${DRY_RUN}" in
  yes|no) ;;
  *)
    echo "ERROR: DRY_RUN must be yes or no" >&2
    exit 1
    ;;
esac

case "${CREATE_SYMLINKS}" in
  yes|no) ;;
  *)
    echo "ERROR: CREATE_SYMLINKS must be yes or no" >&2
    exit 1
    ;;
esac

run_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'

  if [[ "${DRY_RUN}" == "no" ]]; then
    "$@"
  fi
}

archive_one() {
  local legacy="$1"
  local target="$2"
  local name
  local archived

  name="$(basename "${legacy}")"
  archived="${ARCHIVE_ROOT}/${name}"

  echo
  echo "Legacy: ${legacy}"
  echo "Target: ${target}"
  echo "Archive: ${archived}"

  if [[ ! -e "${target}" ]]; then
    echo "ERROR: target root does not exist: ${target}" >&2
    return 1
  fi

  if [[ -L "${legacy}" ]]; then
    echo "[SKIP] legacy path is already a symlink: ${legacy}"
    return 0
  fi

  if [[ ! -e "${legacy}" ]]; then
    echo "[SKIP] legacy path does not exist: ${legacy}"
    return 0
  fi

  if [[ -e "${archived}" ]]; then
    echo "ERROR: archive path already exists: ${archived}" >&2
    return 1
  fi

  run_cmd mkdir -p "${ARCHIVE_ROOT}"
  run_cmd mv "${legacy}" "${archived}"

  if [[ "${CREATE_SYMLINKS}" == "yes" ]]; then
    run_cmd ln -s "${target}" "${legacy}"
  fi
}

echo "SB5 legacy storage archive"
echo "SB5 root       : ${SB5_ROOT}"
echo "Archive root   : ${ARCHIVE_ROOT}"
echo "Dry run        : ${DRY_RUN}"
echo "Create symlink : ${CREATE_SYMLINKS}"
echo
echo "Protected roots are not touched:"
echo "  ${SB5_ROOT}/downscaled"
echo "  ${SB5_ROOT}/ocean_downscaling_products*"
echo "Canonical roots are not archived:"
echo "  ${SB5_ROOT}/reanalysis"
echo "  ${SB5_ROOT}/ipcc_esgf"

archive_one \
  "${SB5_ROOT}/glorys12v1_monthly_0p05" \
  "${SB5_ROOT}/reanalysis/glorys12v1/monthly_0p05"

archive_one \
  "${SB5_ROOT}/global_ocean_biogeochemistry_hindcast_monthly_0p25" \
  "${SB5_ROOT}/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p25"

archive_one \
  "${SB5_ROOT}/global_ocean_biogeochemistry_hindcast_monthly_0p05" \
  "${SB5_ROOT}/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05"

archive_one \
  "${SB5_ROOT}/global_ocean_biogeochemistry_hindcast_monthly_0p05_glorys_coast" \
  "${SB5_ROOT}/reanalysis/global_ocean_biogeochemistry_hindcast/monthly_0p05_glorys_coast"

archive_one \
  "${SB5_ROOT}/ipcc_esgf_downloads" \
  "${SB5_ROOT}/ipcc_esgf/downloads"

archive_one \
  "${SB5_ROOT}/ipcc_esgf_monthly_1deg" \
  "${SB5_ROOT}/ipcc_esgf/monthly_1deg"

archive_one \
  "${SB5_ROOT}/rcp85" \
  "${SB5_ROOT}/ipcc_esgf/cmip5_rcp85"

echo
if [[ "${DRY_RUN}" == "yes" ]]; then
  echo "Dry run complete. Re-run with DRY_RUN=no to archive legacy roots."
else
  echo "Archive complete."
  echo "Rollback pattern, if needed:"
  echo "  mv <legacy_symlink> <legacy_symlink>.bad"
  echo "  mv ${ARCHIVE_ROOT}/<legacy_name> <legacy_path>"
fi
