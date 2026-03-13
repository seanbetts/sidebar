#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDEBAR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
UPLOAD_SCRIPT="${SIDEBAR_DIR}/ci_scripts/upload_sentry_dsyms.sh"

log() {
    echo "sentry-post-xcodebuild: $*"
}

archive_candidates=(
    "${CI_ARCHIVE_PATH:-}"
    "${ARCHIVE_PATH:-}"
    "/Volumes/workspace/build.xcarchive"
)

ARCHIVE_PATH_FOUND=""
for candidate in "${archive_candidates[@]}"; do
    if [[ -n "${candidate}" && -d "${candidate}" ]]; then
        ARCHIVE_PATH_FOUND="${candidate}"
        break
    fi
done

if [[ -z "${ARCHIVE_PATH_FOUND}" ]]; then
    log "skipping upload because archive path does not exist"
    exit 0
fi

if [[ ! -d "${ARCHIVE_PATH_FOUND}/dSYMs" ]]; then
    log "skipping upload because archive dSYMs directory does not exist: ${ARCHIVE_PATH_FOUND}/dSYMs"
    exit 0
fi

found_dsym=0
while IFS= read -r -d '' dsym_path; do
    found_dsym=1
    log "uploading archived dSYM ${dsym_path}"
    CONFIGURATION=Release \
    PLATFORM_NAME=iphoneos \
    SENTRY_DSYM_PATH="${dsym_path}" \
    "${UPLOAD_SCRIPT}"
done < <(find "${ARCHIVE_PATH_FOUND}/dSYMs" -maxdepth 1 -type d -name '*.dSYM' -print0)

if [[ "${found_dsym}" -eq 0 ]]; then
    log "skipping upload because no archived dSYMs were found in ${ARCHIVE_PATH_FOUND}/dSYMs"
    exit 0
fi
