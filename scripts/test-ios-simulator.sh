#!/bin/bash
# Simulator management helpers for test-ios.sh

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
