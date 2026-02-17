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
IOS_WARNING_CONFIG="${IOS_WARNING_CONFIG:-scripts/ios_quality_gates.json}"

temp_dir=""
if [[ -n "${IOS_RESULT_BUNDLE_PATH:-}" ]]; then
  IOS_RESULT_BUNDLE_PATH="${IOS_RESULT_BUNDLE_PATH}"
  mkdir -p "$(dirname "${IOS_RESULT_BUNDLE_PATH}")"
else
  temp_dir="$(mktemp -d -t ios-warning-gate-XXXXXX)"
  IOS_RESULT_BUNDLE_PATH="${temp_dir}/warning-gate.xcresult"
fi

cleanup() {
  if [[ -n "${temp_dir}" && -d "${temp_dir}" ]]; then
    rm -rf "${temp_dir}"
  fi
}
trap cleanup EXIT

echo "Running iOS warning gate build for scheme ${IOS_SCHEME} (${IOS_DESTINATION})..."
xcodebuild \
  -project "${IOS_PROJECT}" \
  -scheme "${IOS_SCHEME}" \
  -destination "${IOS_DESTINATION}" \
  -destination-timeout "${IOS_DESTINATION_TIMEOUT}" \
  -parallel-testing-enabled NO \
  -resultBundlePath "${IOS_RESULT_BUNDLE_PATH}" \
  build

python3 scripts/check_ios_quality_gates.py \
  --xcresult "${IOS_RESULT_BUNDLE_PATH}" \
  --config "${IOS_WARNING_CONFIG}" \
  --warnings-only
