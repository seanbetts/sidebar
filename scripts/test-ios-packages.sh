#!/bin/bash
# Swift Package Manager resolution helpers for test-ios.sh

run_xcodebuild_with_timeout() {
  local timeout_seconds="$1"
  shift

  python3 - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys
import time

timeout_seconds = int(sys.argv[1])
command = sys.argv[2:]

process = subprocess.Popen(command)
deadline = time.monotonic() + timeout_seconds

while True:
    status = process.poll()
    if status is not None:
        sys.exit(status)
    if time.monotonic() >= deadline:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        print(
            f"Command timed out after {timeout_seconds} seconds: {' '.join(command)}",
            file=sys.stderr,
        )
        sys.exit(124)
    time.sleep(1)
PY
}

resolve_package_dependencies() {
  local attempt=1
  while [[ ${attempt} -le ${IOS_PACKAGE_RESOLVE_RETRIES} ]]; do
    local package_args=(
      -resolvePackageDependencies
      -project "${IOS_PROJECT}"
      -scheme "${IOS_EXECUTION_SCHEME}"
    )

    if [[ -n "${IOS_DERIVED_DATA_PATH}" ]]; then
      package_args+=(-derivedDataPath "${IOS_DERIVED_DATA_PATH}")
    fi

    if [[ -n "${IOS_CLONED_SOURCE_PACKAGES_DIR}" ]]; then
      mkdir -p "${IOS_CLONED_SOURCE_PACKAGES_DIR}"
      package_args+=(-clonedSourcePackagesDirPath "${IOS_CLONED_SOURCE_PACKAGES_DIR}")
    fi

    if [[ -n "${IOS_PACKAGE_CACHE_PATH}" ]]; then
      mkdir -p "${IOS_PACKAGE_CACHE_PATH}"
      package_args+=(-packageCachePath "${IOS_PACKAGE_CACHE_PATH}")
    fi

    if [[ "${IOS_ONLY_USE_PACKAGE_VERSIONS_FROM_RESOLVED_FILE}" == "YES" ]]; then
      package_args+=(-onlyUsePackageVersionsFromResolvedFile)
    fi

    if [[ "${IOS_SKIP_PACKAGE_UPDATES}" == "YES" ]]; then
      package_args+=(-skipPackageUpdates)
    fi

    echo "Resolve package dependencies (attempt ${attempt}/${IOS_PACKAGE_RESOLVE_RETRIES})..."
    set +e
    run_xcodebuild_with_timeout "${IOS_PACKAGE_RESOLVE_TIMEOUT_SECONDS}" xcodebuild "${package_args[@]}"
    local resolve_status=$?
    set -e

    if [[ ${resolve_status} -eq 0 ]]; then
      return 0
    fi

    if [[ ${attempt} -eq ${IOS_PACKAGE_RESOLVE_RETRIES} ]]; then
      echo "Package resolution failed after ${IOS_PACKAGE_RESOLVE_RETRIES} attempts."
      return "${resolve_status}"
    fi

    if [[ ${resolve_status} -eq 124 ]]; then
      echo "Package resolution timed out; retrying without clearing SwiftPM caches first..."
    else
      echo "Package resolution failed (exit ${resolve_status}). Clearing SwiftPM caches before retry..."
      if [[ -n "${IOS_DERIVED_DATA_PATH}" ]]; then
        rm -rf "${IOS_DERIVED_DATA_PATH}/SourcePackages"
      fi
      if [[ -n "${IOS_CLONED_SOURCE_PACKAGES_DIR}" ]]; then
        rm -rf "${IOS_CLONED_SOURCE_PACKAGES_DIR}"
      fi
      if [[ "${IOS_CLEAN_GLOBAL_SWIFTPM_CACHE_ON_RETRY}" == "YES" ]]; then
        rm -rf "${HOME}/Library/Caches/org.swift.swiftpm/artifacts"
        rm -rf "${HOME}/Library/Caches/org.swift.swiftpm/repositories"
        rm -rf "${HOME}/Library/Caches/org.swift.swiftpm/manifests"
      fi
    fi

    sleep $((IOS_PACKAGE_RESOLVE_RETRY_DELAY_SECONDS * attempt))
    attempt=$((attempt + 1))
  done
}
