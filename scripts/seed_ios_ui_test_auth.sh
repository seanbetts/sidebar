#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/seed_ios_ui_test_auth.sh --email you@example.com [--password 'secret']

Options:
  --email <email>       Supabase account email to authenticate.
  --password <value>    Supabase account password. If omitted, the script prompts securely.
  --help                Show this help text.

Environment:
  Reads SUPABASE_URL and SUPABASE_ANON_KEY from .env.local.

Output:
  Prints the Xcode scheme environment variables needed to bypass simulator login:
    SIDEBAR_UI_TEST_ACCESS_TOKEN=...
    SIDEBAR_UI_TEST_USER_ID=...
    SIDEBAR_UI_TEST_USE_IN_MEMORY_AUTH=1
EOF
}

load_env() {
  if [[ -f "${REPO_ROOT}/.env.local" ]]; then
    set -a
    source "${REPO_ROOT}/.env.local"
    set +a
    return
  fi

  echo "Missing ${REPO_ROOT}/.env.local" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required value in .env.local: ${name}" >&2
    exit 1
  fi
}

parse_args() {
  EMAIL=""
  PASSWORD=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --email)
        EMAIL="${2:-}"
        shift 2
        ;;
      --password)
        PASSWORD="${2:-}"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "${EMAIL}" ]]; then
    echo "--email is required" >&2
    usage >&2
    exit 1
  fi

  if [[ -z "${PASSWORD}" ]]; then
    read -r -s -p "Supabase password: " PASSWORD
    echo
  fi

  if [[ -z "${PASSWORD}" ]]; then
    echo "Password cannot be empty" >&2
    exit 1
  fi
}

request_seeded_session() {
  local response_file
  local status_code
  response_file="$(mktemp)"
  trap 'rm -f "${response_file}"' EXIT

  status_code="$(
    curl -sS \
      -o "${response_file}" \
      -w '%{http_code}' \
      -X POST "${SUPABASE_URL}/auth/v1/token?grant_type=password" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -H "apikey: ${SUPABASE_ANON_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
      -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}"
  )"

  if [[ ! "${status_code}" =~ ^2 ]]; then
    echo "Supabase auth bootstrap failed with HTTP ${status_code}" >&2
    cat "${response_file}" >&2
    exit 1
  fi

  if command -v jq >/dev/null 2>&1; then
    ACCESS_TOKEN="$(jq -r '.access_token // empty' "${response_file}")"
    USER_ID="$(jq -r '.user.id // empty' "${response_file}")"
  else
    readarray -t parsed_lines < <(
      python3 - "${response_file}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

print(payload.get("access_token", ""))
print((payload.get("user") or {}).get("id", ""))
PY
    )
    ACCESS_TOKEN="${parsed_lines[0]:-}"
    USER_ID="${parsed_lines[1]:-}"
  fi

  if [[ -z "${ACCESS_TOKEN}" || -z "${USER_ID}" ]]; then
    echo "Supabase auth bootstrap succeeded but response was missing access_token or user.id" >&2
    cat "${response_file}" >&2
    exit 1
  fi
}

print_scheme_vars() {
  printf 'SIDEBAR_UI_TEST_ACCESS_TOKEN=%s\n' "${ACCESS_TOKEN}"
  printf 'SIDEBAR_UI_TEST_USER_ID=%s\n' "${USER_ID}"
  printf 'SIDEBAR_UI_TEST_USE_IN_MEMORY_AUTH=1\n'
}

main() {
  load_env
  require_env SUPABASE_URL
  require_env SUPABASE_ANON_KEY
  parse_args "$@"
  request_seeded_session
  print_scheme_vars
}

main "$@"
