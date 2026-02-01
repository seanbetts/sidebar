#!/bin/bash
set -euo pipefail

load_env() {
  local env_file=""
  if [[ -f ".env.local" ]]; then
    env_file=".env.local"
  elif [[ -f ".env" ]]; then
    env_file=".env"
  fi

  if [[ -z "${env_file}" ]]; then
    return
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ -z "${line}" || "${line}" == \#* || "${line}" != *"="* ]]; then
      continue
    fi
    key="${line%%=*}"
    value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    if [[ -z "${key}" || -n "${!key+x}" ]]; then
      continue
    fi
    export "${key}=${value}"
  done < "${env_file}"
}

use_supabase=0

get_env_value() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    echo "${!name}"
    return
  fi
}

prompt_supabase_password() {
  local password
  read -r -s -p "Supabase DB password: " password
  echo
  if [[ -z "${password}" ]]; then
    echo "Password is required."
    exit 1
  fi
  echo "${password}"
}

urlencode() {
  python3 - <<'PY' "$1"
import sys
from urllib.parse import quote_plus

print(quote_plus(sys.argv[1]))
PY
}

prompt_supabase_url() {
  local url
  read -r -p "Supabase pooler URL (no password): " url
  if [[ -z "${url}" ]]; then
    echo "Pooler URL is required."
    exit 1
  fi
  echo "${url}"
}

parse_pooler_url() {
  local url="$1"
  local remainder userinfo hostinfo hostport host port parsed_db parsed_user

  remainder="${url#*://}"
  userinfo="${remainder%@*}"
  hostinfo="${remainder#*@}"

  parsed_user="${userinfo%%:*}"
  hostport="${hostinfo%%/*}"
  parsed_db="${hostinfo#*/}"
  parsed_db="${parsed_db%%\?*}"

  if [[ "${hostport}" == *":"* ]]; then
    host="${hostport%%:*}"
    port="${hostport##*:}"
  else
    host="${hostport}"
    port="5432"
  fi

  echo "${parsed_user}|${host}|${port}|${parsed_db}"
}

configure_supabase() {
  local pooler_host
  local project_id
  local pooler_user
  local pooler_port
  local db_name
  local sslmode
  local pooler_url
  local password

  pooler_host=$(get_env_value SUPABASE_POOLER_HOST)
  project_id=$(get_env_value SUPABASE_PROJECT_ID)
  pooler_user=$(get_env_value SUPABASE_POOLER_USER)
  pooler_port=$(get_env_value SUPABASE_POOLER_PORT)
  db_name=$(get_env_value SUPABASE_DB_NAME)
  sslmode=$(get_env_value SUPABASE_SSLMODE)
  pooler_url=$(get_env_value SUPABASE_POOLER_URL)

  if [[ -z "${pooler_host}" && -z "${pooler_url}" ]]; then
    pooler_url=$(prompt_supabase_url)
  fi

  if [[ -n "${pooler_url}" ]]; then
    IFS="|" read -r parsed_user parsed_host parsed_port parsed_db < <(parse_pooler_url "${pooler_url}")
    if [[ -n "${parsed_user}" ]]; then
      pooler_user="${parsed_user}"
    fi
    if [[ -z "${pooler_host}" && -n "${parsed_host}" ]]; then
      pooler_host="${parsed_host}"
    fi
    if [[ -z "${pooler_port}" && -n "${parsed_port}" ]]; then
      pooler_port="${parsed_port}"
    fi
    if [[ -z "${db_name}" && -n "${parsed_db}" ]]; then
      db_name="${parsed_db}"
    fi
  fi

  if [[ -z "${pooler_host}" ]]; then
    echo "Missing SUPABASE_POOLER_HOST."
    exit 1
  fi

  if [[ -z "${pooler_user}" ]]; then
    if [[ -n "${project_id}" ]]; then
      pooler_user="postgres.${project_id}"
    else
      echo "Missing SUPABASE_POOLER_USER (or SUPABASE_PROJECT_ID)."
      exit 1
    fi
  fi

  pooler_port="${pooler_port:-5432}"
  db_name="${db_name:-postgres}"
  sslmode="${sslmode:-require}"

  password=$(prompt_supabase_password)
  password="${password//$'\n'/}"
  password="${password//$'\r'/}"
  password_encoded=$(urlencode "${password}")
  export DATABASE_URL="postgresql://${pooler_user}:${password_encoded}@${pooler_host}:${pooler_port}/${db_name}?sslmode=${sslmode}"
  export DATABASE_URL_DIRECT="${DATABASE_URL//%/%%}"
  echo
  echo "Using Supabase pooler: user=${pooler_user} host=${pooler_host} port=${pooler_port} db=${db_name}"
}

load_env

if [[ "${1:-}" == "--supabase" ]]; then
  use_supabase=1
  shift
fi

if [[ ${use_supabase} -eq 1 ]]; then
  configure_supabase
fi

export APP_ENV="local"
export AUTH_DEV_MODE="true"
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-dummy}"

cd backend

.venv/bin/python - <<'PY'
import json
from fastapi.testclient import TestClient
from api.main import app

client = TestClient(app)

response = client.post(
    "/api/files/youtube",
    headers={"Authorization": "Bearer test"},
    data=json.dumps({"url": "https://youtu.be/x6oE-X6wuBw?si=gN7qXRG9Nd0C0ckb"}),
)
print("status", response.status_code)
print(response.text)
PY
