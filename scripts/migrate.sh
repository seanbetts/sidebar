#!/bin/bash
set -euo pipefail

load_env() {
  if [[ -f ".env.local" ]]; then
    set -a
    source .env.local
    set +a
  elif [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
  fi
}

use_doppler=0
use_supabase=0

detect_doppler() {
  if command -v doppler >/dev/null 2>&1; then
    if [[ -n "${DOPPLER_TOKEN:-}" || -n "${DOPPLER_PROJECT:-}" || -n "${DOPPLER_CONFIG:-}" ]]; then
      use_doppler=1
    fi
  fi
}

run_alembic() {
  local cmd=("$@")
  local env_args=()

  if [[ -n "${DATABASE_URL:-}" ]]; then
    env_args+=("DATABASE_URL=${DATABASE_URL}")
  fi
  if [[ -n "${APP_ENV:-}" ]]; then
    env_args+=("APP_ENV=${APP_ENV}")
  fi
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    env_args+=("ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
  fi

  if [[ ${use_doppler} -eq 1 ]]; then
    doppler run -- env "${env_args[@]}" uv run "${cmd[@]}"
  else
    env "${env_args[@]}" uv run "${cmd[@]}"
  fi
}

get_env_value() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    echo "${!name}"
    return
  fi
  if [[ ${use_doppler} -eq 1 ]]; then
    doppler run -- printenv "${name}" 2>/dev/null || true
  fi
}

is_prod_db() {
  local database_url
  local project_id
  local pooler_host

  database_url=$(get_env_value DATABASE_URL)
  project_id=$(get_env_value SUPABASE_PROJECT_ID)
  pooler_host=$(get_env_value SUPABASE_POOLER_HOST)

  if [[ -n "${database_url}" && "${database_url}" == *"supabase.co"* ]]; then
    return 0
  fi
  if [[ -n "${project_id}" || -n "${pooler_host}" ]]; then
    return 0
  fi
  return 1
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

  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    export ANTHROPIC_API_KEY="dummy"
  fi

  password=$(prompt_supabase_password)
  password_encoded=$(urlencode "${password}")
  export DATABASE_URL="postgresql://${pooler_user}:${password_encoded}@${pooler_host}:${pooler_port}/${db_name}?sslmode=${sslmode}"
  export DATABASE_URL_DIRECT="${DATABASE_URL}"
  export APP_ENV="production"
  echo "Using Supabase pooler: user=${pooler_user} host=${pooler_host} port=${pooler_port} db=${db_name}"
  use_doppler=0
}

load_env
detect_doppler

if is_prod_db && [[ "${ALLOW_PROD_MIGRATIONS:-}" != "true" ]]; then
  echo "Refusing to run migrations against Supabase without ALLOW_PROD_MIGRATIONS=true"
  exit 1
fi

if [[ "${1:-}" == "--supabase" ]]; then
  use_supabase=1
  shift
fi

COMMAND="${1:-}"
ARG="${2:-}"

if [[ -z "${COMMAND}" ]]; then
  echo "Usage: ./scripts/migrate.sh [--supabase] [upgrade|downgrade|create|stamp|history|current] [args]"
  exit 1
fi

if [[ ${use_supabase} -eq 1 ]]; then
  configure_supabase
fi

cd backend

case "${COMMAND}" in
  upgrade)
    run_alembic alembic -c api/alembic.ini upgrade "${ARG:-head}"
    ;;
  downgrade)
    run_alembic alembic -c api/alembic.ini downgrade "${ARG:--1}"
    ;;
  stamp)
    if [[ -z "${ARG}" ]]; then
      echo "Usage: ./scripts/migrate.sh stamp \"revision\""
      exit 1
    fi
    run_alembic alembic -c api/alembic.ini stamp "${ARG}"
    ;;
  create)
    if [[ -z "${ARG}" ]]; then
      echo "Usage: ./scripts/migrate.sh create \"message\""
      exit 1
    fi
    run_alembic alembic -c api/alembic.ini revision --autogenerate -m "${ARG}"
    ;;
  history)
    run_alembic alembic -c api/alembic.ini history
    ;;
  current)
    run_alembic alembic -c api/alembic.ini current
    ;;
  *)
    echo "Unknown command: ${COMMAND}"
    echo "Usage: ./scripts/migrate.sh [--supabase] [upgrade|downgrade|create|stamp|history|current] [args]"
    exit 1
    ;;
esac
