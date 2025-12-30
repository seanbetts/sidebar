#!/bin/bash
set -euo pipefail

errors=0

note() {
  echo "[info] $1"
}

warn() {
  echo "[warn] $1"
}

fail() {
  echo "[error] $1"
  errors=$((errors + 1))
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    fail "Missing required command: ${cmd}"
  else
    note "Found ${cmd}"
  fi
}

load_env() {
  if [[ -f ".env.local" ]]; then
    set -a
    source .env.local
    set +a
    note "Loaded .env.local"
  elif [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
    note "Loaded .env"
  else
    warn "No .env.local or .env found"
  fi
}

check_env_var() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "${value}" ]]; then
    fail "Missing environment variable: ${name}"
  else
    note "${name} is set"
  fi
}

port_available() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
      fail "Port ${port} is already in use"
    else
      note "Port ${port} is available"
    fi
  else
    note "Skipping port check for ${port} (lsof not available)"
  fi
}

load_env

require_cmd python3
require_cmd node
require_cmd npm
require_cmd uv

if [[ -d "backend/.venv" ]]; then
  note "Found backend/.venv"
else
  warn "backend/.venv not found (run 'cd backend && uv sync')"
fi

if [[ -d "frontend/node_modules" ]]; then
  note "Found frontend/node_modules"
else
  warn "frontend/node_modules not found (run 'cd frontend && npm install')"
fi

check_env_var AUTH_DEV_MODE
check_env_var DEFAULT_USER_ID
check_env_var API_URL
check_env_var SUPABASE_PROJECT_ID
check_env_var SUPABASE_POSTGRES_PSWD
check_env_var R2_ENDPOINT
check_env_var R2_BUCKET
check_env_var R2_ACCESS_KEY_ID
check_env_var R2_SECRET_ACCESS_KEY
check_env_var ANTHROPIC_API_KEY

if [[ "${SUPABASE_USE_POOLER:-true}" =~ ^(1|true|yes|on)$ ]]; then
  check_env_var SUPABASE_POOLER_HOST
else
  check_env_var SUPABASE_DB_USER
fi

port_available 8001
port_available 3000

if [[ -d "backend/.venv" ]]; then
  note "Checking database connectivity..."
  if ! (cd backend && uv run python - <<'PY'
from sqlalchemy import create_engine, text
from api.config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)
with engine.connect() as conn:
    conn.execute(text("SELECT 1"))
print("Database connection OK")
PY
  ); then
    fail "Database connection failed"
  fi
else
  warn "Skipping database connectivity check (backend/.venv missing)"
fi

if [[ ${errors} -gt 0 ]]; then
  echo "Health check failed with ${errors} error(s)."
  exit 1
fi

echo "Health check passed."
