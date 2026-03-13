#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDEBAR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RETRY_ATTEMPTS="${SENTRY_UPLOAD_RETRY_ATTEMPTS:-3}"
RETRY_DELAY_SECONDS="${SENTRY_UPLOAD_RETRY_DELAY_SECONDS:-5}"

log() {
    echo "sentry-dsym-upload: $*"
}

is_transient_upload_failure() {
    local output="$1"

    [[ "${output}" == *"Could not resolve host"* ]] ||
    [[ "${output}" == *"could not resolve host"* ]] ||
    [[ "${output}" == *"Failed to connect"* ]] ||
    [[ "${output}" == *"Connection timed out"* ]] ||
    [[ "${output}" == *"Operation timed out"* ]] ||
    [[ "${output}" == *"network error"* ]] ||
    [[ "${output}" == *"temporarily unavailable"* ]] ||
    [[ "${output}" == *"timeout"* ]] ||
    [[ "${output}" == *"HTTP 502"* ]] ||
    [[ "${output}" == *"HTTP 503"* ]] ||
    [[ "${output}" == *"HTTP 504"* ]]
}

run_upload_with_retry() {
    local sentry_cli="$1"
    local dsym_path="$2"
    local attempt=1
    local output=""
    local exit_code=0

    while (( attempt <= RETRY_ATTEMPTS )); do
        set +e
        output="$("${sentry_cli}" debug-files upload \
            --org "${SENTRY_ORG}" \
            --project "${SENTRY_PROJECT}" \
            "${dsym_path}" 2>&1)"
        exit_code=$?
        set -e

        if [[ "${exit_code}" -eq 0 ]]; then
            [[ -n "${output}" ]] && echo "${output}"
            return 0
        fi

        echo "${output}"
        if (( attempt < RETRY_ATTEMPTS )); then
            log "upload attempt ${attempt}/${RETRY_ATTEMPTS} failed, retrying in ${RETRY_DELAY_SECONDS}s"
            sleep "${RETRY_DELAY_SECONDS}"
        fi

        ((attempt++))
    done

    if is_transient_upload_failure "${output}"; then
        log "warning: transient Sentry upload failure after ${RETRY_ATTEMPTS} attempts; continuing without failing the archive"
        return 0
    fi

    log "error: non-transient Sentry upload failure"
    return "${exit_code}"
}

find_sentry_cli() {
    local candidates=(
        "${SENTRY_CLI_PATH:-}"
        "${SIDEBAR_DIR}/.tools/sentry-cli/bin/sentry-cli"
    )
    local path_cli
    path_cli="$(command -v sentry-cli 2>/dev/null || true)"
    candidates+=("${path_cli}")

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -n "${candidate}" && -x "${candidate}" ]]; then
            echo "${candidate}"
            return 0
        fi
    done

    return 1
}

if [[ "${CONFIGURATION:-}" != "Release" ]]; then
    log "skipping upload for non-Release configuration '${CONFIGURATION:-unknown}'"
    exit 0
fi

if [[ "${PLATFORM_NAME:-}" == *simulator* ]] || [[ "${EFFECTIVE_PLATFORM_NAME:-}" == *simulator* ]]; then
    log "skipping upload for simulator build"
    exit 0
fi

missing_vars=()
for var in SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT; do
    if [[ -z "${!var:-}" ]]; then
        missing_vars+=("${var}")
    fi
done

if (( ${#missing_vars[@]} > 0 )); then
    log "skipping upload because Sentry auth/project env is incomplete (${missing_vars[*]})"
    exit 0
fi

DSYM_PATH="${SENTRY_DSYM_PATH:-}"
if [[ -z "${DSYM_PATH}" ]]; then
    if [[ -z "${DWARF_DSYM_FOLDER_PATH:-}" || -z "${DWARF_DSYM_FILE_NAME:-}" ]]; then
        log "skipping upload because dSYM build settings are unavailable"
        exit 0
    fi
    DSYM_PATH="${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}"
fi

if [[ ! -d "${DSYM_PATH}" ]]; then
    log "skipping upload because dSYM path does not exist: ${DSYM_PATH}"
    exit 0
fi

if ! SENTRY_CLI="$(find_sentry_cli)"; then
    log "error: sentry-cli is required when SENTRY_AUTH_TOKEN, SENTRY_ORG, and SENTRY_PROJECT are set"
    log "error: install it via ios/sideBar/ci_scripts/ci_post_clone.sh or set SENTRY_CLI_PATH"
    exit 1
fi

DSYM_NAME="$(basename "${DSYM_PATH}")"
log "uploading ${DSYM_NAME} for ${PRODUCT_BUNDLE_IDENTIFIER:-unknown-bundle-id}"
run_upload_with_retry "${SENTRY_CLI}" "${DSYM_PATH}"
log "upload complete"
