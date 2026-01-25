#!/bin/bash
set -euo pipefail

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild not found. Install Xcode and ensure xcodebuild is on PATH."
  exit 1
fi

IOS_PROJECT="${IOS_PROJECT:-ios/sideBar/sideBar.xcodeproj}"
IOS_SCHEME="${IOS_SCHEME:-sideBar}"
IOS_DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"

echo "Running iOS tests for scheme ${IOS_SCHEME} (${IOS_DESTINATION})..."

xcodebuild \
  -project "${IOS_PROJECT}" \
  -scheme "${IOS_SCHEME}" \
  -destination "${IOS_DESTINATION}" \
  test
