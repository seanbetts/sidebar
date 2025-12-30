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

detect_doppler() {
  if command -v doppler >/dev/null 2>&1; then
    if [[ -n "${DOPPLER_TOKEN:-}" || -n "${DOPPLER_PROJECT:-}" || -n "${DOPPLER_CONFIG:-}" ]]; then
      use_doppler=1
    fi
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

load_env
detect_doppler

if is_prod_db && [[ "${ALLOW_PROD_MIGRATIONS:-}" != "true" ]]; then
  echo "Refusing to run migrations against Supabase without ALLOW_PROD_MIGRATIONS=true"
  exit 1
fi

COMMAND="${1:-}"
ARG="${2:-}"

if [[ -z "${COMMAND}" ]]; then
  echo "Usage: ./scripts/migrate.sh [upgrade|downgrade|create|history|current] [args]"
  exit 1
fi

cd backend

case "${COMMAND}" in
  upgrade)
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run -- uv run alembic -c api/alembic.ini upgrade "${ARG:-head}"
    else
      uv run alembic -c api/alembic.ini upgrade "${ARG:-head}"
    fi
    ;;
  downgrade)
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run -- uv run alembic -c api/alembic.ini downgrade "${ARG:--1}"
    else
      uv run alembic -c api/alembic.ini downgrade "${ARG:--1}"
    fi
    ;;
  create)
    if [[ -z "${ARG}" ]]; then
      echo "Usage: ./scripts/migrate.sh create \"message\""
      exit 1
    fi
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run -- uv run alembic -c api/alembic.ini revision --autogenerate -m "${ARG}"
    else
      uv run alembic -c api/alembic.ini revision --autogenerate -m "${ARG}"
    fi
    ;;
  history)
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run -- uv run alembic -c api/alembic.ini history
    else
      uv run alembic -c api/alembic.ini history
    fi
    ;;
  current)
    if [[ ${use_doppler} -eq 1 ]]; then
      doppler run -- uv run alembic -c api/alembic.ini current
    else
      uv run alembic -c api/alembic.ini current
    fi
    ;;
  *)
    echo "Unknown command: ${COMMAND}"
    echo "Usage: ./scripts/migrate.sh [upgrade|downgrade|create|history|current] [args]"
    exit 1
    ;;
esac
