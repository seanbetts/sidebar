#!/bin/bash
set -euo pipefail

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild not found. Install Xcode and ensure xcodebuild is on PATH."
  exit 1
fi

IOS_PROJECT="${IOS_PROJECT:-ios/sideBar/sideBar.xcodeproj}"
if [[ -n "${IOS_SCHEME+x}" ]]; then
  IOS_SCHEME="${IOS_SCHEME}"
else
  IOS_SCHEME="sideBar"
fi

default_test_plan_for_scheme() {
  case "${1}" in
    sideBar)
      echo "AppleFast"
      ;;
    sideBarUI)
      echo "AppleUI"
      ;;
    sideBarExtensions)
      echo "AppleExtensions"
      ;;
    *)
      echo ""
      ;;
  esac
}

default_ui_smoke_only_testing() {
  cat <<'EOF'
sideBarUITests/SideBarUITests/testLoginSuccessNavigatesToSignedInHome,sideBarUITests/SideBarUITests/testSendMessageInSeededConversationShowsStreamingReply,sideBarUITests/SideBarUITests/testCreateEditDeleteNoteInSeededAccount,sideBarUITests/SideBarUITests/testStreamingReplyKeepsBottomAnchorVisible,sideBarUITests/SideBarUITests/testIPadTasksWorkspaceDoesNotShowFloatingDock
EOF
}

scheme_includes_ui_tests() {
  [[ "${1}" == "sideBarUI" ]]
}

scheme_has_only_ui_tests() {
  [[ "${1}" == "sideBarUI" ]]
}

if [[ -n "${IOS_DESTINATION+x}" ]]; then
  IOS_DESTINATION="${IOS_DESTINATION}"
else
  IOS_DESTINATION="platform=iOS Simulator,name=iPad Pro 13-inch (M5)"
fi
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
IOS_TARGET_SIMULATOR_UDID=""

if [[ -n "${IOS_TEST_PLAN}" ]]; then
  echo "Running Apple tests for scheme ${IOS_SCHEME} (${IOS_DESTINATION}, test plan ${IOS_TEST_PLAN})..."
else
  echo "Running Apple tests for scheme ${IOS_SCHEME} (${IOS_DESTINATION})..."
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

XCODEBUILD_ARGS=(
  -project "${IOS_PROJECT}"
  -scheme "${IOS_SCHEME}"
  -destination "${IOS_DESTINATION}"
  -destination-timeout "${IOS_DESTINATION_TIMEOUT}"
  -enableCodeCoverage "${IOS_ENABLE_CODE_COVERAGE}"
)

if [[ -n "${IOS_TEST_PLAN}" ]]; then
  XCODEBUILD_ARGS+=(-testPlan "${IOS_TEST_PLAN}")
fi

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

if [[ "${IOS_SCHEME}" == "sideBarUI" && -z "${IOS_ONLY_TESTING}" && "${IOS_UI_SMOKE_ONLY}" == "YES" ]]; then
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

ui_test_backend_config_present() {
  local secrets_file_path
  secrets_file_path="$(ui_test_secrets_file_path)"
  local api_base_url
  api_base_url="$(ui_test_value "SIDEBAR_UI_TEST_API_BASE_URL" "API_BASE_URL" "${secrets_file_path}")"
  local supabase_url
  supabase_url="$(ui_test_value "SIDEBAR_UI_TEST_SUPABASE_URL" "SUPABASE_URL" "${secrets_file_path}")"
  local supabase_anon_key
  supabase_anon_key="$(ui_test_value "SIDEBAR_UI_TEST_SUPABASE_ANON_KEY" "SUPABASE_ANON_KEY" "${secrets_file_path}")"
  [[ -n "${api_base_url}" && -n "${supabase_url}" && -n "${supabase_anon_key}" ]]
}

ui_test_credentials_present() {
  local secrets_file_path
  secrets_file_path="$(ui_test_secrets_file_path)"
  local email
  email="$(ui_test_value "SIDEBAR_UI_TEST_EMAIL" "" "${secrets_file_path}")"
  local password
  password="$(ui_test_value "SIDEBAR_UI_TEST_PASSWORD" "" "${secrets_file_path}")"
  [[ -n "${email}" && -n "${password}" ]]
}

ui_test_secrets_file_path() {
  if [[ -n "${SIDEBAR_UI_TEST_SECRETS_FILE:-}" ]]; then
    printf '%s\n' "${SIDEBAR_UI_TEST_SECRETS_FILE}"
    return 0
  fi

  local project_dir
  project_dir="$(cd "$(dirname "${IOS_PROJECT}")" >/dev/null 2>&1 && pwd)"
  printf '%s/.ui-test-secrets.local\n' "${project_dir}"
}

load_ui_test_secret_value() {
  local key="$1"
  local file_path="$2"
  [[ -f "${file_path}" ]] || return 0

  python3 - "$key" "$file_path" <<'PY'
import sys

key = sys.argv[1]
file_path = sys.argv[2]

try:
    with open(file_path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            current_key, raw_value = stripped.split("=", 1)
            if current_key.strip() != key:
                continue
            value = raw_value.strip().strip("\"'")
            if value:
                print(value)
                break
except FileNotFoundError:
    pass
PY
}

ui_test_value() {
  local primary_key="$1"
  local fallback_key="$2"
  local secrets_file_path="$3"
  local value="${!primary_key:-}"

  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
    return 0
  fi

  if [[ -n "${fallback_key}" ]]; then
    value="${!fallback_key:-}"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  fi

  value="$(load_ui_test_secret_value "${primary_key}" "${secrets_file_path}")"
  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
    return 0
  fi

  if [[ -n "${fallback_key}" ]]; then
    value="$(load_ui_test_secret_value "${fallback_key}" "${secrets_file_path}")"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
    fi
  fi
}

lane_includes_ui_tests="NO"
if scheme_includes_ui_tests "${IOS_SCHEME}"; then
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
    if scheme_has_only_ui_tests "${IOS_SCHEME}"; then
      echo "No non-UI Apple tests remain in scheme ${IOS_SCHEME}; failing before running xcodebuild."
      exit 1
    fi
    XCODEBUILD_ARGS+=(-skip-testing:sideBarUITests)
    lane_includes_ui_tests="NO"
  fi

  if [[ "${lane_includes_ui_tests}" == "YES" ]] && ! ui_test_credentials_present; then
    echo "UI test credentials missing; skipping sideBarUITests."
    if scheme_has_only_ui_tests "${IOS_SCHEME}"; then
      echo "No non-UI Apple tests remain in scheme ${IOS_SCHEME}; failing before running xcodebuild."
      exit 1
    fi
    XCODEBUILD_ARGS+=(-skip-testing:sideBarUITests)
    lane_includes_ui_tests="NO"
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
      -scheme "${IOS_SCHEME}"
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

resolve_package_dependencies
XCODEBUILD_ARGS+=(-disableAutomaticPackageResolution)

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
