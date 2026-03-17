#!/bin/bash
set -euo pipefail

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild not found. Install Xcode and ensure xcodebuild is on PATH."
  exit 1
fi

# shellcheck source=scripts/test-ios-schemes.sh
source "$(dirname "$0")/test-ios-schemes.sh"
# shellcheck source=scripts/test-ios-ui-secrets.sh
source "$(dirname "$0")/test-ios-ui-secrets.sh"
# shellcheck source=scripts/test-ios-simulator.sh
source "$(dirname "$0")/test-ios-simulator.sh"
# shellcheck source=scripts/test-ios-packages.sh
source "$(dirname "$0")/test-ios-packages.sh"

IOS_PROJECT="${IOS_PROJECT:-ios/sideBar/sideBar.xcodeproj}"
if [[ -n "${IOS_SCHEME+x}" ]]; then
  IOS_SCHEME="${IOS_SCHEME}"
else
  IOS_SCHEME="sideBar"
fi

if [[ -n "${IOS_DESTINATION+x}" ]]; then
  IOS_DESTINATION="${IOS_DESTINATION}"
else
  IOS_DESTINATION="platform=iOS Simulator,name=iPad Pro 13-inch (M5)"
fi
SIDEBAR_PRE_PUSH_MODE="${SIDEBAR_PRE_PUSH_MODE:-NO}"
SIDEBAR_PRE_PUSH_STATE_DIR="${SIDEBAR_PRE_PUSH_STATE_DIR:-}"
SIDEBAR_PRE_PUSH_SIMULATOR_NAME="${SIDEBAR_PRE_PUSH_SIMULATOR_NAME:-}"
IOS_DESTINATION_TIMEOUT="${IOS_DESTINATION_TIMEOUT:-120}"
if [[ -n "${IOS_ENABLE_CODE_COVERAGE+x}" ]]; then
  IOS_ENABLE_CODE_COVERAGE="${IOS_ENABLE_CODE_COVERAGE}"
elif [[ "${IOS_SCHEME}" == "sideBar" ]]; then
  IOS_ENABLE_CODE_COVERAGE="NO"
else
  IOS_ENABLE_CODE_COVERAGE="YES"
fi
if [[ -n "${IOS_TEST_PLAN+x}" ]]; then
  IOS_TEST_PLAN="${IOS_TEST_PLAN}"
else
  IOS_TEST_PLAN="$(default_test_plan_for_scheme "${IOS_SCHEME}")"
fi
IOS_EXECUTION_SCHEME="$(resolve_execution_scheme "${IOS_SCHEME}" "${IOS_TEST_PLAN}")"
IOS_RESULT_BUNDLE_PATH="${IOS_RESULT_BUNDLE_PATH:-}"
IOS_DERIVED_DATA_PATH="${IOS_DERIVED_DATA_PATH:-}"
IOS_CLEAN_DERIVED_DATA="${IOS_CLEAN_DERIVED_DATA:-NO}"
IOS_ONLY_TESTING="${IOS_ONLY_TESTING:-}"
IOS_SKIP_TESTING="${IOS_SKIP_TESTING:-}"
IOS_UI_SMOKE_ONLY="${IOS_UI_SMOKE_ONLY:-YES}"
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
IOS_PACKAGE_RESOLVE_TIMEOUT_SECONDS="${IOS_PACKAGE_RESOLVE_TIMEOUT_SECONDS:-180}"
IOS_CLEAN_GLOBAL_SWIFTPM_CACHE_ON_RETRY="${IOS_CLEAN_GLOBAL_SWIFTPM_CACHE_ON_RETRY:-YES}"
IOS_SKIP_PACKAGE_DEPENDENCY_RESOLUTION="${IOS_SKIP_PACKAGE_DEPENDENCY_RESOLUTION:-NO}"
IOS_RESOLVE_PACKAGE_DEPENDENCIES_ONLY="${IOS_RESOLVE_PACKAGE_DEPENDENCIES_ONLY:-NO}"
IOS_CLONED_SOURCE_PACKAGES_DIR="${IOS_CLONED_SOURCE_PACKAGES_DIR:-}"
IOS_PACKAGE_CACHE_PATH="${IOS_PACKAGE_CACHE_PATH:-}"
if [[ -n "${IOS_ONLY_USE_PACKAGE_VERSIONS_FROM_RESOLVED_FILE+x}" ]]; then
  IOS_ONLY_USE_PACKAGE_VERSIONS_FROM_RESOLVED_FILE="${IOS_ONLY_USE_PACKAGE_VERSIONS_FROM_RESOLVED_FILE}"
elif [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  IOS_ONLY_USE_PACKAGE_VERSIONS_FROM_RESOLVED_FILE="YES"
else
  IOS_ONLY_USE_PACKAGE_VERSIONS_FROM_RESOLVED_FILE="NO"
fi
if [[ -n "${IOS_SKIP_PACKAGE_UPDATES+x}" ]]; then
  IOS_SKIP_PACKAGE_UPDATES="${IOS_SKIP_PACKAGE_UPDATES}"
elif [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  IOS_SKIP_PACKAGE_UPDATES="YES"
else
  IOS_SKIP_PACKAGE_UPDATES="NO"
fi
IOS_PREPARE_SIMULATOR_BEFORE_TESTS="${IOS_PREPARE_SIMULATOR_BEFORE_TESTS:-NO}"
IOS_COLLECT_SIMULATOR_DIAGNOSTICS_ON_FAILURE="${IOS_COLLECT_SIMULATOR_DIAGNOSTICS_ON_FAILURE:-NO}"
IOS_SIMULATOR_DIAGNOSTICS_DIR="${IOS_SIMULATOR_DIAGNOSTICS_DIR:-}"
IOS_RETRY_TRANSIENT_SIMULATOR_FAILURES="${IOS_RETRY_TRANSIENT_SIMULATOR_FAILURES:-YES}"
IOS_TRANSIENT_SIMULATOR_FAILURE_RETRY_LIMIT="${IOS_TRANSIENT_SIMULATOR_FAILURE_RETRY_LIMIT:-3}"
IOS_TARGET_SIMULATOR_UDID=""

if [[ "${SIDEBAR_PRE_PUSH_MODE}" == "YES" ]]; then
  # Keep pre-push simulator resolution isolated from generic test execution.
  # The helper owns dedicated simulator reuse/creation and destination rewriting.
  # shellcheck source=/dev/null
  source "$(dirname "$0")/test-ios-pre-push-simulator.sh"
  if ! IOS_TARGET_SIMULATOR_UDID="$(ensure_pre_push_simulator_udid)"; then
    if [[ -n "${IOS_TARGET_SIMULATOR_UDID}" ]]; then
      printf '%s\n' "${IOS_TARGET_SIMULATOR_UDID}"
    fi
    exit 1
  fi
  IOS_DESTINATION="platform=iOS Simulator,id=${IOS_TARGET_SIMULATOR_UDID}"
fi

if [[ "${IOS_EXECUTION_SCHEME}" != "${IOS_SCHEME}" ]]; then
  echo "Routing Apple tests from scheme ${IOS_SCHEME} to ${IOS_EXECUTION_SCHEME} for test plan ${IOS_TEST_PLAN}."
fi

if [[ -n "${IOS_TEST_PLAN}" ]]; then
  echo "Running Apple tests for scheme ${IOS_EXECUTION_SCHEME} (${IOS_DESTINATION}, test plan ${IOS_TEST_PLAN})..."
else
  echo "Running Apple tests for scheme ${IOS_EXECUTION_SCHEME} (${IOS_DESTINATION})..."
fi

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  # CI runners occasionally inherit an http://github.com rewrite which breaks SwiftPM fetches.
  # Use an ephemeral per-job git config rather than mutating ~/.gitconfig on a shared runner.
  ios_ci_git_config="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/sidebar-ci-gitconfig.XXXXXX")"
  if [[ -f "${HOME}/.gitconfig" ]]; then
    cp "${HOME}/.gitconfig" "${ios_ci_git_config}"
  fi
  git config --file "${ios_ci_git_config}" --unset-all url.http://github.com/.insteadOf || true
  git config --file "${ios_ci_git_config}" url."https://github.com/".insteadOf "http://github.com/"
  # HTTP/1.1 is generally more reliable for SwiftPM clone traffic in CI.
  git config --file "${ios_ci_git_config}" http.version HTTP/1.1
  export GIT_CONFIG_GLOBAL="${ios_ci_git_config}"
fi

remove_existing_result_bundle() {
  if [[ -n "${IOS_RESULT_BUNDLE_PATH}" && -e "${IOS_RESULT_BUNDLE_PATH}" ]]; then
    echo "Removing existing result bundle at ${IOS_RESULT_BUNDLE_PATH}..."
    rm -rf "${IOS_RESULT_BUNDLE_PATH}"
  fi
}

XCODEBUILD_ARGS=(
  -project "${IOS_PROJECT}"
  -scheme "${IOS_EXECUTION_SCHEME}"
  -destination "${IOS_DESTINATION}"
  -destination-timeout "${IOS_DESTINATION_TIMEOUT}"
  -enableCodeCoverage "${IOS_ENABLE_CODE_COVERAGE}"
)

if [[ -n "${IOS_TEST_PLAN}" ]]; then
  XCODEBUILD_ARGS+=(-testPlan "${IOS_TEST_PLAN}")
fi

if [[ -n "${IOS_RESULT_BUNDLE_PATH}" ]]; then
  if [[ "${IOS_RESULT_BUNDLE_PATH}" == "/" ]]; then
    echo "Error: IOS_RESULT_BUNDLE_PATH cannot be '/'."
    exit 1
  fi
  remove_existing_result_bundle
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

if [[ -n "${IOS_CLONED_SOURCE_PACKAGES_DIR}" ]]; then
  if [[ "${IOS_CLONED_SOURCE_PACKAGES_DIR}" == "/" ]]; then
    echo "Error: IOS_CLONED_SOURCE_PACKAGES_DIR cannot be '/'."
    exit 1
  fi
  mkdir -p "${IOS_CLONED_SOURCE_PACKAGES_DIR}"
  XCODEBUILD_ARGS+=(-clonedSourcePackagesDirPath "${IOS_CLONED_SOURCE_PACKAGES_DIR}")
fi

if [[ -n "${IOS_PACKAGE_CACHE_PATH}" ]]; then
  if [[ "${IOS_PACKAGE_CACHE_PATH}" == "/" ]]; then
    echo "Error: IOS_PACKAGE_CACHE_PATH cannot be '/'."
    exit 1
  fi
  mkdir -p "${IOS_PACKAGE_CACHE_PATH}"
  XCODEBUILD_ARGS+=(-packageCachePath "${IOS_PACKAGE_CACHE_PATH}")
fi

if [[ "${IOS_ONLY_USE_PACKAGE_VERSIONS_FROM_RESOLVED_FILE}" == "YES" ]]; then
  XCODEBUILD_ARGS+=(-onlyUsePackageVersionsFromResolvedFile)
fi

if [[ "${IOS_SKIP_PACKAGE_UPDATES}" == "YES" ]]; then
  XCODEBUILD_ARGS+=(-skipPackageUpdates)
fi

if [[ "${IOS_EXECUTION_SCHEME}" == "sideBarUI" && -z "${IOS_ONLY_TESTING}" && "${IOS_UI_SMOKE_ONLY}" == "YES" ]]; then
  IOS_ONLY_TESTING="$(default_ui_smoke_only_testing)"
  echo "Defaulting sideBarUI to curated smoke coverage. Set IOS_UI_SMOKE_ONLY=NO or IOS_ONLY_TESTING to run a broader UI selection."
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

if [[ "${IOS_RESOLVE_PACKAGE_DEPENDENCIES_ONLY}" == "YES" ]]; then
  resolve_only_mode="YES"
else
  resolve_only_mode="NO"
fi

lane_includes_ui_tests="NO"

if [[ "${resolve_only_mode}" != "YES" ]]; then
  if scheme_includes_ui_tests "${IOS_EXECUTION_SCHEME}"; then
    lane_includes_ui_tests="YES"
  fi

  if [[ "${lane_includes_ui_tests}" == "YES" ]]; then
    if [[ -n "${IOS_ONLY_TESTING}" ]]; then
      IFS=',' read -r -a only_testing_specs_for_ui <<< "${IOS_ONLY_TESTING}"
      lane_includes_ui_tests="NO"
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

    if [[ "${lane_includes_ui_tests}" == "YES" ]] && ! ui_test_backend_config_present; then
      echo "UI test backend configuration missing; skipping sideBarUITests."
      if scheme_has_only_ui_tests "${IOS_EXECUTION_SCHEME}"; then
        echo "No non-UI Apple tests remain in scheme ${IOS_EXECUTION_SCHEME}; failing before running xcodebuild."
        exit 1
      fi
      XCODEBUILD_ARGS+=(-skip-testing:sideBarUITests)
      lane_includes_ui_tests="NO"
    fi

    if [[ "${lane_includes_ui_tests}" == "YES" ]] && ! ui_test_credentials_present; then
      echo "UI test credentials missing; skipping sideBarUITests."
      if scheme_has_only_ui_tests "${IOS_EXECUTION_SCHEME}"; then
        echo "No non-UI Apple tests remain in scheme ${IOS_EXECUTION_SCHEME}; failing before running xcodebuild."
        exit 1
      fi
      XCODEBUILD_ARGS+=(-skip-testing:sideBarUITests)
      lane_includes_ui_tests="NO"
    fi
  fi
fi

if [[ -z "${IOS_PARALLEL_TESTING_ENABLED}" ]]; then
  if [[ "${IOS_DESTINATION}" == *"platform=iOS Simulator"* ]]; then
    # Default iOS simulator lanes to serial execution. Parallel clones have been
    # the main source of xctrunner/app launch flakes in local hooks.
    IOS_PARALLEL_TESTING_ENABLED="NO"
  elif [[ "${IOS_DESTINATION}" == *"platform=macOS"* ]]; then
    # Keep the default macOS hook lane deterministic. A few legacy UI-adjacent
    # unit tests still share mutable process state and only flake under parallel workers.
    IOS_PARALLEL_TESTING_ENABLED="NO"
  elif [[ "${lane_includes_ui_tests}" == "YES" ]]; then
    IOS_PARALLEL_TESTING_ENABLED="NO"
  else
    IOS_PARALLEL_TESTING_ENABLED="YES"
  fi
fi

if [[ -z "${IOS_MAXIMUM_PARALLEL_TESTING_WORKERS}" && "${ios_parallel_testing_setting_supplied}" == "NO" && ( "${lane_includes_ui_tests}" == "YES" || "${IOS_DESTINATION}" == *"platform=iOS Simulator"* || "${IOS_DESTINATION}" == *"platform=macOS"* ) ]]; then
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

if [[ "${IOS_SKIP_PACKAGE_DEPENDENCY_RESOLUTION}" != "YES" ]]; then
  resolve_package_dependencies
else
  echo "Skipping explicit package resolution before test execution."
fi

if [[ "${IOS_RESOLVE_PACKAGE_DEPENDENCIES_ONLY}" == "YES" ]]; then
  echo "Package resolution complete; exiting before test execution."
  exit 0
fi

XCODEBUILD_ARGS+=(-disableAutomaticPackageResolution)

prepare_target_simulator

ui_only_lane_executed_zero_runnable_tests() {
  local test_results_summary="$1"

  python3 - "$test_results_summary" <<'PY'
import json
import sys

raw = sys.argv[1]
if not raw.strip():
    sys.exit(0)

try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)

total = int(payload.get("totalTestCount", 0) or 0)
skipped = int(payload.get("skippedTests", 0) or 0)

if total == 0 or (total > 0 and skipped == total):
    sys.exit(0)

sys.exit(1)
PY
}

is_transient_simulator_infrastructure_failure() {
  local output_path="$1"
  local test_results_summary="$2"
  local build_results_summary="$3"

  [[ "${IOS_RETRY_TRANSIENT_SIMULATOR_FAILURES}" == "YES" ]] || return 1
  is_ios_simulator_destination || return 1

  local combined_output
  combined_output="$(
    {
      cat "${output_path}" 2>/dev/null || true
      printf '%s\n' "${test_results_summary}"
      printf '%s\n' "${build_results_summary}"
    }
  )"

  if [[ "${combined_output}" == *"Failed to create a bundle instance representing"* ]] \
    && [[ "${combined_output}" == *"Test crashed with signal kill."* ]]; then
    return 0
  fi

  if [[ "${combined_output}" == *"Restarting after unexpected exit, crash, or test timeout"* ]] \
    && [[ "${combined_output}" == *"malloc: *** error for object"* ]] \
    && [[ "${combined_output}" == *"pointer being freed was not allocated"* ]]; then
    return 0
  fi

  [[ "${combined_output}" == *"Failed to install or launch the test runner"* ]] || return 1
  [[ "${combined_output}" == *"Mach error -308"* || "${combined_output}" == *"(ipc/mig) server died"* ]] || return 1

  return 0
}

test_status=0
test_attempt=1
while [[ ${test_attempt} -le ${IOS_TRANSIENT_SIMULATOR_FAILURE_RETRY_LIMIT} ]]; do
  xcodebuild_output_file="$(mktemp "${TMPDIR:-/tmp}/sidebar-test-ios-xcodebuild.XXXXXX")"
  set +e
  xcodebuild "${XCODEBUILD_ARGS[@]}" test 2>&1 | tee "${xcodebuild_output_file}"
  test_status=${PIPESTATUS[0]}
  set -e

  test_results_summary=""
  build_results_summary=""
  if [[ ${test_status} -ne 0 ]]; then
    collect_simulator_diagnostics
    if [[ -n "${IOS_RESULT_BUNDLE_PATH}" && -d "${IOS_RESULT_BUNDLE_PATH}" ]]; then
      test_results_summary="$(xcrun xcresulttool get test-results summary --path "${IOS_RESULT_BUNDLE_PATH}" --compact || true)"
      build_results_summary="$(xcrun xcresulttool get build-results --path "${IOS_RESULT_BUNDLE_PATH}" --compact || true)"

      if [[ ${test_status} -eq 73 ]] \
        && [[ "${build_results_summary}" == *"\"status\":\"succeeded\""* ]] \
        && [[ "${build_results_summary}" == *"\"errorCount\":0"* ]]; then
        if [[ "${test_results_summary}" == *"\"totalTestCount\":0"* ]] || [[ -z "${test_results_summary}" ]]; then
          echo "xcodebuild exited 73, and xcresult reports zero executed tests; treating this as a failure."
        else
          echo "xcodebuild exited 73, but xcresult reports a successful build/test action with zero errors and executed tests; continuing."
          test_status=0
        fi
      fi
    fi
  fi

  if [[ ${test_status} -eq 0 ]]; then
    if [[ "${lane_includes_ui_tests}" == "YES" ]] && scheme_has_only_ui_tests "${IOS_EXECUTION_SCHEME}" \
      && [[ -n "${IOS_RESULT_BUNDLE_PATH}" && -d "${IOS_RESULT_BUNDLE_PATH}" ]]; then
      test_results_summary="$(xcrun xcresulttool get test-results summary --path "${IOS_RESULT_BUNDLE_PATH}" --compact || true)"
      if ui_only_lane_executed_zero_runnable_tests "${test_results_summary}"; then
        echo "UI-only lane executed zero runnable tests because all selected UI tests were skipped."
        echo "xcodebuild test summary:"
        echo "${test_results_summary}"
        test_status=1
      fi
    fi

    if [[ ${test_status} -eq 0 ]]; then
      rm -f "${xcodebuild_output_file}"
      break
    fi

    rm -f "${xcodebuild_output_file}"
    break
  fi

  if [[ ${test_attempt} -lt ${IOS_TRANSIENT_SIMULATOR_FAILURE_RETRY_LIMIT} ]] \
    && is_transient_simulator_infrastructure_failure "${xcodebuild_output_file}" "${test_results_summary}" "${build_results_summary}"; then
    echo "Detected transient simulator infrastructure failure (attempt ${test_attempt}/${IOS_TRANSIENT_SIMULATOR_FAILURE_RETRY_LIMIT}); retrying xcodebuild test."
    remove_existing_result_bundle
    prepare_target_simulator
    rm -f "${xcodebuild_output_file}"
    test_attempt=$((test_attempt + 1))
    continue
  fi

  if [[ -n "${test_results_summary}" || -n "${build_results_summary}" ]]; then
    echo "xcodebuild failed (exit ${test_status}). xcresult summary:"
    echo "${test_results_summary}"
    echo "${build_results_summary}"
  fi

  rm -f "${xcodebuild_output_file}"
  break
done

if [[ ${test_status} -ne 0 ]]; then
  exit "${test_status}"
fi
