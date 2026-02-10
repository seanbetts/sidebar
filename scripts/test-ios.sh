#!/bin/bash
set -euo pipefail

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild not found. Install Xcode and ensure xcodebuild is on PATH."
  exit 1
fi

IOS_PROJECT="${IOS_PROJECT:-ios/sideBar/sideBar.xcodeproj}"
IOS_SCHEME="${IOS_SCHEME:-sideBar}"
IOS_DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"
IOS_ENABLE_CODE_COVERAGE="${IOS_ENABLE_CODE_COVERAGE:-YES}"
IOS_RESULT_BUNDLE_PATH="${IOS_RESULT_BUNDLE_PATH:-}"
IOS_ONLY_TESTING="${IOS_ONLY_TESTING:-}"
IOS_SKIP_TESTING="${IOS_SKIP_TESTING:-}"
IOS_RETRY_TESTS_ON_FAILURE="${IOS_RETRY_TESTS_ON_FAILURE:-NO}"
IOS_TEST_ITERATIONS="${IOS_TEST_ITERATIONS:-2}"

echo "Running iOS tests for scheme ${IOS_SCHEME} (${IOS_DESTINATION})..."

XCODEBUILD_ARGS=(
  -project "${IOS_PROJECT}"
  -scheme "${IOS_SCHEME}"
  -destination "${IOS_DESTINATION}"
  -enableCodeCoverage "${IOS_ENABLE_CODE_COVERAGE}"
)

if [[ -n "${IOS_RESULT_BUNDLE_PATH}" ]]; then
  mkdir -p "$(dirname "${IOS_RESULT_BUNDLE_PATH}")"
  XCODEBUILD_ARGS+=(-resultBundlePath "${IOS_RESULT_BUNDLE_PATH}")
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

if [[ "${IOS_RETRY_TESTS_ON_FAILURE}" == "YES" ]]; then
  XCODEBUILD_ARGS+=(
    -retry-tests-on-failure
    -test-iterations "${IOS_TEST_ITERATIONS}"
  )
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
    echo "xcodebuild failed (exit ${status}). xcresult summary:"
    xcrun xcresulttool get test-results summary --path "${IOS_RESULT_BUNDLE_PATH}" --compact || true
    xcrun xcresulttool get build-results --path "${IOS_RESULT_BUNDLE_PATH}" --compact || true
  fi
  exit "${status}"
fi
