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

is_prod_db() {
  if [[ -n "${DATABASE_URL:-}" && "${DATABASE_URL}" == *"supabase.co"* ]]; then
    return 0
  fi
  if [[ -n "${SUPABASE_PROJECT_ID:-}" || -n "${SUPABASE_POOLER_HOST:-}" ]]; then
    return 0
  fi
  return 1
}

load_env

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
    uv run alembic -c api/alembic.ini upgrade "${ARG:-head}"
    ;;
  downgrade)
    uv run alembic -c api/alembic.ini downgrade "${ARG:--1}"
    ;;
  create)
    if [[ -z "${ARG}" ]]; then
      echo "Usage: ./scripts/migrate.sh create \"message\""
      exit 1
    fi
    uv run alembic -c api/alembic.ini revision --autogenerate -m "${ARG}"
    ;;
  history)
    uv run alembic -c api/alembic.ini history
    ;;
  current)
    uv run alembic -c api/alembic.ini current
    ;;
  *)
    echo "Unknown command: ${COMMAND}"
    echo "Usage: ./scripts/migrate.sh [upgrade|downgrade|create|history|current] [args]"
    exit 1
    ;;
esac
