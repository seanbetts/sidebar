#!/bin/bash
# UI test secret resolution helpers for test-ios.sh

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
