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
if [[ -n "${IOS_PARALLEL_TESTING_ENABLED+x}" ]]; then
  ios_parallel_testing_setting_supplied="YES"
else
  ios_parallel_testing_setting_supplied="NO"
fi
IOS_PARALLEL_TESTING_ENABLED="${IOS_PARALLEL_TESTING_ENABLED:-}"
IOS_MAXIMUM_PARALLEL_TESTING_WORKERS="${IOS_MAXIMUM_PARALLEL_TESTING_WORKERS:-}"

echo "Running iOS tests for scheme ${IOS_SCHEME} (${IOS_DESTINATION})..."

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

set +e
xcodebuild "${XCODEBUILD_ARGS[@]}" test
status=$?
set -e

if [[ ${status} -ne 0 ]]; then
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
