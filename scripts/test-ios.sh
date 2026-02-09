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

if [[ "${IOS_DESTINATION}" == *"platform=macOS"* ]]; then
  # CI macOS runners do not have signing certificates/profiles.
  XCODEBUILD_ARGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=
  )
  # macOS UI tests are not reliable in headless CI sessions.
  if [[ "${IOS_SKIP_UI_TESTS_ON_MACOS:-YES}" != "NO" ]]; then
    XCODEBUILD_ARGS+=(-skip-testing:sideBarUITests)
  fi
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" test
