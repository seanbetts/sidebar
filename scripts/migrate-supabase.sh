#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/migrate-supabase.sh [upgrade|downgrade|stamp|current|history|revision] [arg]

Required env:
  SUPABASE_POOLER_HOST   e.g. aws-1-eu-central-1.pooler.supabase.com

Optional env:
  SUPABASE_POOLER_USER   defaults to postgres.$SUPABASE_PROJECT_ID
  SUPABASE_PROJECT_ID    used to build default user
  SUPABASE_POOLER_PORT   defaults to 5432 (session pooler)
  SUPABASE_DB_NAME       defaults to postgres
  SUPABASE_SSLMODE       defaults to require
  ANTHROPIC_API_KEY      defaults to dummy if unset

Examples:
  SUPABASE_POOLER_HOST=aws-1-eu-central-1.pooler.supabase.com \
  SUPABASE_PROJECT_ID=ixsexuxkmklbfvrnrybm \
  ./scripts/migrate-supabase.sh upgrade head
EOF
}

COMMAND="${1:-}"
ARG="${2:-}"

if [[ -z "${COMMAND}" ]]; then
  usage
  exit 1
fi

SUPABASE_POOLER_HOST="${SUPABASE_POOLER_HOST:-}"
if [[ -z "${SUPABASE_POOLER_HOST}" ]]; then
  echo "Missing SUPABASE_POOLER_HOST."
  usage
  exit 1
fi

SUPABASE_PROJECT_ID="${SUPABASE_PROJECT_ID:-}"
SUPABASE_POOLER_USER="${SUPABASE_POOLER_USER:-}"
if [[ -z "${SUPABASE_POOLER_USER}" ]]; then
  if [[ -n "${SUPABASE_PROJECT_ID}" ]]; then
    SUPABASE_POOLER_USER="postgres.${SUPABASE_PROJECT_ID}"
  else
    echo "Missing SUPABASE_POOLER_USER (or SUPABASE_PROJECT_ID)."
    usage
    exit 1
  fi
fi

SUPABASE_POOLER_PORT="${SUPABASE_POOLER_PORT:-5432}"
SUPABASE_DB_NAME="${SUPABASE_DB_NAME:-postgres}"
SUPABASE_SSLMODE="${SUPABASE_SSLMODE:-require}"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  export ANTHROPIC_API_KEY="dummy"
fi

read -r -s -p "Supabase DB password: " SUPABASE_PASSWORD
echo
if [[ -z "${SUPABASE_PASSWORD}" ]]; then
  echo "Password is required."
  exit 1
fi

export DATABASE_URL_DIRECT="postgresql://${SUPABASE_POOLER_USER}:${SUPABASE_PASSWORD}@${SUPABASE_POOLER_HOST}:${SUPABASE_POOLER_PORT}/${SUPABASE_DB_NAME}?sslmode=${SUPABASE_SSLMODE}"

cd backend

case "${COMMAND}" in
  upgrade)
    alembic -c api/alembic.ini upgrade "${ARG:-head}"
    ;;
  downgrade)
    alembic -c api/alembic.ini downgrade "${ARG:--1}"
    ;;
  stamp)
    if [[ -z "${ARG}" ]]; then
      echo "stamp requires a revision id."
      exit 1
    fi
    alembic -c api/alembic.ini stamp "${ARG}"
    ;;
  current)
    alembic -c api/alembic.ini current
    ;;
  history)
    alembic -c api/alembic.ini history
    ;;
  revision)
    if [[ -z "${ARG}" ]]; then
      echo "revision requires a message."
      exit 1
    fi
    alembic -c api/alembic.ini revision --autogenerate -m "${ARG}"
    ;;
  *)
    echo "Unknown command: ${COMMAND}"
    usage
    exit 1
    ;;
esac
