#!/bin/bash

pre_push_destination_device_name() {
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

resolve_pre_push_runtime_id() {
  xcrun simctl list runtimes --json | python3 -c '
import json
import re
import sys

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    raise SystemExit(0)
matches = []
for runtime in payload.get("runtimes", []):
    if not runtime.get("isAvailable", False):
        continue
    platform = str(runtime.get("platform", ""))
    identifier = str(runtime.get("identifier", ""))
    if platform != "iOS" and ".iOS-" not in identifier:
        continue
    version = str(runtime.get("version", ""))
    version_key = tuple(int(part) for part in re.findall(r"\d+", version))
    matches.append((version_key, identifier))

if matches:
    matches.sort()
    print(matches[-1][1])
'
}

resolve_pre_push_device_type_id() {
  local device_name="$1"
  xcrun simctl list devicetypes --json | python3 -c '
import json
import sys

device_name = sys.argv[1]
try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    raise SystemExit(0)
for device_type in payload.get("devicetypes", []):
    if device_type.get("name") == device_name:
        print(device_type.get("identifier", ""))
        break
' "${device_name}"
}

resolve_named_pre_push_simulator_udid() {
  local simulator_name="$1"
  xcrun simctl list devices available --json | python3 -c '
import json
import sys

simulator_name = sys.argv[1]
try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    raise SystemExit(0)
matches = []
for runtime, devices in payload.get("devices", {}).items():
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        if device.get("name") != simulator_name:
            continue
        matches.append((device.get("state") == "Booted", runtime, device.get("udid", "")))

matches.sort(reverse=True)
if matches:
    print(matches[0][2])
' "${simulator_name}"
}

stored_pre_push_simulator_udid_is_valid() {
  local stored_udid="$1"
  [[ -n "${stored_udid}" ]] || return 1

  local named_udid
  named_udid="$(xcrun simctl list devices available --json | python3 -c '
import json
import sys

stored_udid = sys.argv[1]
simulator_name = sys.argv[2]
try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    raise SystemExit(0)
for devices in payload.get("devices", {}).values():
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        if device.get("udid") == stored_udid and device.get("name") == simulator_name:
            print(stored_udid)
            raise SystemExit(0)
' "${stored_udid}" "${SIDEBAR_PRE_PUSH_SIMULATOR_NAME}")"
  [[ "${named_udid}" == "${stored_udid}" ]]
}

ensure_pre_push_simulator_udid() {
  local state_dir="${SIDEBAR_PRE_PUSH_STATE_DIR:-}"
  local simulator_name="${SIDEBAR_PRE_PUSH_SIMULATOR_NAME:-}"

  if [[ -z "${state_dir}" ]]; then
    echo "Error: SIDEBAR_PRE_PUSH_STATE_DIR is required when SIDEBAR_PRE_PUSH_MODE=YES."
    return 1
  fi

  if [[ -z "${simulator_name}" ]]; then
    echo "Error: SIDEBAR_PRE_PUSH_SIMULATOR_NAME is required when SIDEBAR_PRE_PUSH_MODE=YES."
    return 1
  fi

  mkdir -p "${state_dir}"

  local state_file="${state_dir}/simulator-udid"
  local stored_udid=""
  if [[ -f "${state_file}" ]]; then
    stored_udid="$(<"${state_file}")"
    stored_udid="${stored_udid//$'\n'/}"
  fi

  if stored_pre_push_simulator_udid_is_valid "${stored_udid}"; then
    printf '%s\n' "${stored_udid}" > "${state_file}"
    printf '%s\n' "${stored_udid}"
    return 0
  fi

  local resolved_udid
  resolved_udid="$(resolve_named_pre_push_simulator_udid "${simulator_name}")"
  if [[ -n "${resolved_udid}" ]]; then
    printf '%s\n' "${resolved_udid}" > "${state_file}"
    printf '%s\n' "${resolved_udid}"
    return 0
  fi

  local runtime_id
  runtime_id="$(resolve_pre_push_runtime_id)"
  if [[ -z "${runtime_id}" ]]; then
    echo "Error: could not resolve an available iOS simulator runtime for pre-push mode."
    return 1
  fi

  local device_name
  device_name="$(pre_push_destination_device_name)"
  local device_type_id
  device_type_id="$(resolve_pre_push_device_type_id "${device_name}")"
  if [[ -z "${device_type_id}" ]]; then
    echo "Error: could not resolve simulator device type for destination ${IOS_DESTINATION}."
    return 1
  fi

  resolved_udid="$(xcrun simctl create "${simulator_name}" "${device_type_id}" "${runtime_id}")"
  printf '%s\n' "${resolved_udid}" > "${state_file}"
  printf '%s\n' "${resolved_udid}"
}
