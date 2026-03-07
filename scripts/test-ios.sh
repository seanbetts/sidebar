#!/bin/bash
set -euo pipefail

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild not found. Install Xcode and ensure xcodebuild is on PATH."
  exit 1
fi

IOS_PROJECT="${IOS_PROJECT:-ios/sideBar/sideBar.xcodeproj}"
IOS_SCHEME="${IOS_SCHEME:-sideBar}"
IOS_DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"
IOS_DESTINATION_TIMEOUT="${IOS_DESTINATION_TIMEOUT:-120}"
IOS_ENABLE_CODE_COVERAGE="${IOS_ENABLE_CODE_COVERAGE:-YES}"
IOS_RESULT_BUNDLE_PATH="${IOS_RESULT_BUNDLE_PATH:-}"
IOS_DERIVED_DATA_PATH="${IOS_DERIVED_DATA_PATH:-}"
IOS_CLEAN_DERIVED_DATA="${IOS_CLEAN_DERIVED_DATA:-NO}"
IOS_ONLY_TESTING="${IOS_ONLY_TESTING:-}"
IOS_SKIP_TESTING="${IOS_SKIP_TESTING:-}"
IOS_RETRY_TESTS_ON_FAILURE="${IOS_RETRY_TESTS_ON_FAILURE:-NO}"
IOS_TEST_ITERATIONS="${IOS_TEST_ITERATIONS:-2}"
IOS_SKIP_LAUNCH_UI_TESTS="${IOS_SKIP_LAUNCH_UI_TESTS:-YES}"
if [[ -n "${IOS_PARALLEL_TESTING_ENABLED+x}" ]]; then
  ios_parallel_testing_setting_supplied="YES"
else
  ios_parallel_testing_setting_supplied="NO"
fi
IOS_PARALLEL_TESTING_ENABLED="${IOS_PARALLEL_TESTING_ENABLED:-}"
IOS_MAXIMUM_PARALLEL_TESTING_WORKERS="${IOS_MAXIMUM_PARALLEL_TESTING_WORKERS:-}"
IOS_PACKAGE_RESOLVE_RETRIES="${IOS_PACKAGE_RESOLVE_RETRIES:-4}"
IOS_PACKAGE_RESOLVE_RETRY_DELAY_SECONDS="${IOS_PACKAGE_RESOLVE_RETRY_DELAY_SECONDS:-15}"
IOS_CLEAN_GLOBAL_SWIFTPM_CACHE_ON_RETRY="${IOS_CLEAN_GLOBAL_SWIFTPM_CACHE_ON_RETRY:-YES}"
IOS_PREPARE_SIMULATOR_BEFORE_TESTS="${IOS_PREPARE_SIMULATOR_BEFORE_TESTS:-NO}"
IOS_COLLECT_SIMULATOR_DIAGNOSTICS_ON_FAILURE="${IOS_COLLECT_SIMULATOR_DIAGNOSTICS_ON_FAILURE:-NO}"
IOS_SIMULATOR_DIAGNOSTICS_DIR="${IOS_SIMULATOR_DIAGNOSTICS_DIR:-}"
IOS_TARGET_SIMULATOR_UDID=""

echo "Running iOS tests for scheme ${IOS_SCHEME} (${IOS_DESTINATION})..."

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  # CI runners occasionally inherit an http://github.com rewrite which breaks SwiftPM fetches.
  git config --global --unset-all url.http://github.com/.insteadOf || true
  git config --global url."https://github.com/".insteadOf "http://github.com/"
  # HTTP/1.1 is generally more reliable for SwiftPM clone traffic in CI.
  git config --global http.version HTTP/1.1
fi

XCODEBUILD_ARGS=(
  -project "${IOS_PROJECT}"
  -scheme "${IOS_SCHEME}"
  -destination "${IOS_DESTINATION}"
  -destination-timeout "${IOS_DESTINATION_TIMEOUT}"
  -enableCodeCoverage "${IOS_ENABLE_CODE_COVERAGE}"
)

if [[ -n "${IOS_RESULT_BUNDLE_PATH}" ]]; then
  mkdir -p "$(dirname "${IOS_RESULT_BUNDLE_PATH}")"
  XCODEBUILD_ARGS+=(-resultBundlePath "${IOS_RESULT_BUNDLE_PATH}")
fi

if [[ -n "${IOS_DERIVED_DATA_PATH}" ]]; then
  if [[ "${IOS_DERIVED_DATA_PATH}" == "/" ]]; then
    echo "Error: IOS_DERIVED_DATA_PATH cannot be '/'."
    exit 1
  fi
  if [[ "${IOS_CLEAN_DERIVED_DATA}" == "YES" && -d "${IOS_DERIVED_DATA_PATH}" ]]; then
    echo "Cleaning DerivedData at ${IOS_DERIVED_DATA_PATH}..."
    rm -rf "${IOS_DERIVED_DATA_PATH}"
  fi
  mkdir -p "${IOS_DERIVED_DATA_PATH}"
  XCODEBUILD_ARGS+=(-derivedDataPath "${IOS_DERIVED_DATA_PATH}")
fi

if [[ -n "${IOS_ONLY_TESTING}" ]]; then
  IFS=',' read -r -a only_testing_specs <<< "${IOS_ONLY_TESTING}"
  for raw_spec in "${only_testing_specs[@]}"; do
    spec="$(echo "${raw_spec}" | xargs)"
    if [[ -n "${spec}" ]]; then
      XCODEBUILD_ARGS+=("-only-testing:${spec}")
    fi
  done
fi

if [[ -n "${IOS_SKIP_TESTING}" ]]; then
  IFS=',' read -r -a skip_testing_specs <<< "${IOS_SKIP_TESTING}"
  for raw_spec in "${skip_testing_specs[@]}"; do
    spec="$(echo "${raw_spec}" | xargs)"
    if [[ -n "${spec}" ]]; then
      XCODEBUILD_ARGS+=("-skip-testing:${spec}")
    fi
  done
fi

lane_includes_ui_tests="NO"
if [[ "${IOS_SCHEME}" == "sideBar" ]]; then
  if [[ -n "${IOS_ONLY_TESTING}" ]]; then
    IFS=',' read -r -a only_testing_specs_for_ui <<< "${IOS_ONLY_TESTING}"
    for raw_spec in "${only_testing_specs_for_ui[@]}"; do
      spec="$(echo "${raw_spec}" | xargs)"
      target="${spec%%/*}"
      if [[ "${target}" == "sideBarUITests" ]]; then
        lane_includes_ui_tests="YES"
        break
      fi
    done
  else
    lane_includes_ui_tests="YES"
  fi

  if [[ "${lane_includes_ui_tests}" == "YES" && -n "${IOS_SKIP_TESTING}" ]]; then
    IFS=',' read -r -a skip_testing_specs_for_ui <<< "${IOS_SKIP_TESTING}"
    for raw_spec in "${skip_testing_specs_for_ui[@]}"; do
      spec="$(echo "${raw_spec}" | xargs)"
      if [[ "${spec}" == "sideBarUITests" ]]; then
        lane_includes_ui_tests="NO"
        break
      fi
    done
  fi
fi

if [[ -z "${IOS_PARALLEL_TESTING_ENABLED}" ]]; then
  if [[ "${lane_includes_ui_tests}" == "YES" ]]; then
    IOS_PARALLEL_TESTING_ENABLED="NO"
  else
    IOS_PARALLEL_TESTING_ENABLED="YES"
  fi
fi

if [[ "${lane_includes_ui_tests}" == "YES" && -z "${IOS_MAXIMUM_PARALLEL_TESTING_WORKERS}" && "${ios_parallel_testing_setting_supplied}" == "NO" ]]; then
  IOS_MAXIMUM_PARALLEL_TESTING_WORKERS="1"
fi

if [[ "${lane_includes_ui_tests}" == "YES" && "${IOS_SKIP_LAUNCH_UI_TESTS}" == "YES" ]]; then
  if [[ " ${XCODEBUILD_ARGS[*]} " != *" -skip-testing:sideBarUITests/SideBarUITestsLaunchTests "* ]]; then
    echo "Skipping SideBarUITestsLaunchTests for simulator stability."
    XCODEBUILD_ARGS+=(-skip-testing:sideBarUITests/SideBarUITestsLaunchTests)
  fi
fi

if [[ "${IOS_RETRY_TESTS_ON_FAILURE}" == "YES" ]]; then
  XCODEBUILD_ARGS+=(
    -retry-tests-on-failure
    -test-iterations "${IOS_TEST_ITERATIONS}"
  )
fi

if [[ "${IOS_PARALLEL_TESTING_ENABLED}" == "NO" ]]; then
  if [[ "${lane_includes_ui_tests}" == "YES" ]]; then
    echo "UI tests detected in lane; running serially for simulator stability."
  fi
  XCODEBUILD_ARGS+=(-parallel-testing-enabled NO)
fi

if [[ -n "${IOS_MAXIMUM_PARALLEL_TESTING_WORKERS}" ]]; then
  XCODEBUILD_ARGS+=(-maximum-parallel-testing-workers "${IOS_MAXIMUM_PARALLEL_TESTING_WORKERS}")
fi

if [[ "${IOS_DESTINATION}" == *"platform=macOS"* ]]; then
  # CI macOS runners do not have signing certificates/profiles.
  XCODEBUILD_ARGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=
  )
  # macOS UI tests are not reliable in headless CI sessions.
  if [[ "${IOS_SKIP_UI_TESTS_ON_MACOS:-YES}" != "NO" ]]; then
    if [[ " ${XCODEBUILD_ARGS[*]} " != *" -skip-testing:sideBarUITests "* ]]; then
      XCODEBUILD_ARGS+=(-skip-testing:sideBarUITests)
    fi
  fi
fi

is_ios_simulator_destination() {
  [[ "${IOS_DESTINATION}" == *"platform=iOS Simulator"* ]]
}

destination_device_name() {
  python3 - "${IOS_DESTINATION}" <<'PY'
import sys

destination = sys.argv[1]
for part in destination.split(","):
    if "=" not in part:
        continue
    key, value = part.split("=", 1)
    if key.strip() == "name":
        print(value.strip())
        break
PY
}

resolve_target_simulator_udid() {
  local destination_name
  destination_name="$(destination_device_name)"
  if [[ -z "${destination_name}" ]]; then
    return 1
  fi

  xcrun simctl list devices available --json | python3 -c '
import json
import sys

destination_name = sys.argv[1]
payload = json.load(sys.stdin)
matches = []
for runtime, devices in payload.get("devices", {}).items():
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        if device.get("name") != destination_name:
            continue
        matches.append(
            (
                device.get("state") == "Booted",
                runtime,
                device.get("udid", ""),
            )
        )

matches.sort(reverse=True)
if matches:
    print(matches[0][2])
' "${destination_name}"
}

prepare_target_simulator() {
  [[ "${IOS_PREPARE_SIMULATOR_BEFORE_TESTS}" == "YES" ]] || return 0
  is_ios_simulator_destination || return 0

  local destination_name
  destination_name="$(destination_device_name || true)"
  IOS_TARGET_SIMULATOR_UDID="$(resolve_target_simulator_udid || true)"

  if [[ -z "${IOS_TARGET_SIMULATOR_UDID}" ]]; then
    echo "Warning: could not resolve simulator UDID for destination ${IOS_DESTINATION}."
    return 0
  fi

  echo "Preparing simulator ${destination_name} (${IOS_TARGET_SIMULATOR_UDID})..."
  xcrun simctl shutdown "${IOS_TARGET_SIMULATOR_UDID}" >/dev/null 2>&1 || true
  xcrun simctl erase "${IOS_TARGET_SIMULATOR_UDID}" >/dev/null 2>&1 || true
  xcrun simctl boot "${IOS_TARGET_SIMULATOR_UDID}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${IOS_TARGET_SIMULATOR_UDID}" -b
}

collect_simulator_diagnostics() {
  [[ "${IOS_COLLECT_SIMULATOR_DIAGNOSTICS_ON_FAILURE}" == "YES" ]] || return 0
  is_ios_simulator_destination || return 0

  if [[ -z "${IOS_TARGET_SIMULATOR_UDID}" ]]; then
    IOS_TARGET_SIMULATOR_UDID="$(resolve_target_simulator_udid || true)"
  fi

  local diagnostics_dir="${IOS_SIMULATOR_DIAGNOSTICS_DIR}"
  if [[ -z "${diagnostics_dir}" ]]; then
    if [[ -n "${IOS_RESULT_BUNDLE_PATH}" ]]; then
      diagnostics_dir="$(dirname "${IOS_RESULT_BUNDLE_PATH}")/simulator-diagnostics"
    else
      diagnostics_dir="ios-test-results/simulator-diagnostics"
    fi
  fi

  mkdir -p "${diagnostics_dir}"
  echo "Collecting simulator diagnostics in ${diagnostics_dir}..."

  xcrun simctl list devices > "${diagnostics_dir}/simctl-list-devices.txt" 2>&1 || true
  log show \
    --style compact \
    --last 20m \
    --predicate 'process == "Simulator" || process == "CoreSimulatorService" || process == "testmanagerd" || process == "xctest" || process == "sideBar" || eventMessage CONTAINS[c] "sideBar" || eventMessage CONTAINS[c] "xctest"' \
    > "${diagnostics_dir}/host-log-show.txt" 2>&1 || true

  while IFS= read -r -d '' crash_report; do
    cp "${crash_report}" "${diagnostics_dir}/" >/dev/null 2>&1 || true
  done < <(
    find "${HOME}/Library/Logs/DiagnosticReports" \
      -maxdepth 1 \
      \( -name 'sideBar-*.ips' -o -name 'sideBar-*.crash' -o -name 'xctest-*.ips' -o -name 'xctest-*.crash' \) \
      -mmin -30 \
      -print0 2>/dev/null || true
  )

  if [[ -n "${IOS_TARGET_SIMULATOR_UDID}" ]]; then
    printf '%s\n' "${IOS_TARGET_SIMULATOR_UDID}" \
      > "${diagnostics_dir}/target-simulator-udid.txt"
    xcrun simctl spawn "${IOS_TARGET_SIMULATOR_UDID}" launchctl print system \
      > "${diagnostics_dir}/simulator-launchctl.txt" 2>&1 || true
  fi
}

resolve_package_dependencies() {
  local attempt=1
  while [[ ${attempt} -le ${IOS_PACKAGE_RESOLVE_RETRIES} ]]; do
    local package_args=(
      -resolvePackageDependencies
      -project "${IOS_PROJECT}"
      -scheme "${IOS_SCHEME}"
    )

    if [[ -n "${IOS_DERIVED_DATA_PATH}" ]]; then
      package_args+=(-derivedDataPath "${IOS_DERIVED_DATA_PATH}")
    fi

    echo "Resolve package dependencies (attempt ${attempt}/${IOS_PACKAGE_RESOLVE_RETRIES})..."
    set +e
    xcodebuild "${package_args[@]}"
    local resolve_status=$?
    set -e

    if [[ ${resolve_status} -eq 0 ]]; then
      return 0
    fi

    if [[ ${attempt} -eq ${IOS_PACKAGE_RESOLVE_RETRIES} ]]; then
      echo "Package resolution failed after ${IOS_PACKAGE_RESOLVE_RETRIES} attempts."
      return "${resolve_status}"
    fi

    echo "Package resolution failed (exit ${resolve_status}). Clearing SwiftPM caches before retry..."
    if [[ -n "${IOS_DERIVED_DATA_PATH}" ]]; then
      rm -rf "${IOS_DERIVED_DATA_PATH}/SourcePackages"
    fi
    if [[ "${IOS_CLEAN_GLOBAL_SWIFTPM_CACHE_ON_RETRY}" == "YES" ]]; then
      rm -rf "${HOME}/Library/Caches/org.swift.swiftpm/repositories"
      rm -rf "${HOME}/Library/Caches/org.swift.swiftpm/manifests"
    fi

    sleep $((IOS_PACKAGE_RESOLVE_RETRY_DELAY_SECONDS * attempt))
    attempt=$((attempt + 1))
  done
}

resolve_package_dependencies

prepare_target_simulator

set +e
xcodebuild "${XCODEBUILD_ARGS[@]}" test
status=$?
set -e

if [[ ${status} -ne 0 ]]; then
  collect_simulator_diagnostics
  if [[ -n "${IOS_RESULT_BUNDLE_PATH}" && -d "${IOS_RESULT_BUNDLE_PATH}" ]]; then
    test_results_summary="$(xcrun xcresulttool get test-results summary --path "${IOS_RESULT_BUNDLE_PATH}" --compact || true)"
    build_results_summary="$(xcrun xcresulttool get build-results --path "${IOS_RESULT_BUNDLE_PATH}" --compact || true)"

    if [[ ${status} -eq 73 ]] \
      && [[ "${build_results_summary}" == *"\"status\":\"succeeded\""* ]] \
      && [[ "${build_results_summary}" == *"\"errorCount\":0"* ]]; then
      echo "xcodebuild exited 73, but xcresult reports a successful build/test action with zero errors; continuing."
      status=0
    else
      echo "xcodebuild failed (exit ${status}). xcresult summary:"
      echo "${test_results_summary}"
      echo "${build_results_summary}"
    fi
  fi
fi

if [[ ${status} -ne 0 ]]; then
  exit "${status}"
fi
