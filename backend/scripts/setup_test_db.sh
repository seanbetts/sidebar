#!/bin/bash
# Setup test database for running tests.
# Prefers native localhost Postgres (dev.sh workflow), with Docker fallback.

set -euo pipefail

echo "Setting up test database..."

DB_HOST="localhost"
DB_PORT="5433"
DB_USER="sidebar"
DB_PASSWORD="sidebar_dev"
DB_NAME="sidebar_test"

CONTAINER_NAME="sidebar-test-postgres"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/../../docker-compose.test.yml"
SERVICE_NAME="postgres-test"
BACKEND_ROOT="${SCRIPT_DIR}/.."
TEST_DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

ensure_postgres_tools() {
    if command -v psql >/dev/null 2>&1 && command -v pg_isready >/dev/null 2>&1; then
        return 0
    fi

    if ! command -v brew >/dev/null 2>&1; then
        return 1
    fi

    local formula
    local bin_dir
    for formula in postgresql@17 postgresql@16 postgresql@15 postgresql@14 postgresql; do
        if brew list --formula "${formula}" >/dev/null 2>&1; then
            bin_dir="$(brew --prefix "${formula}")/bin"
            if [[ -d "${bin_dir}" ]]; then
                export PATH="${bin_dir}:${PATH}"
                break
            fi
        fi
    done

    command -v psql >/dev/null 2>&1 && command -v pg_isready >/dev/null 2>&1
}

wait_for_native_postgres() {
    local ready=false
    for _ in {1..30}; do
        if PGPASSWORD="${DB_PASSWORD}" pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres >/dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 1
    done

    [[ "${ready}" == "true" ]]
}

detect_native_admin_user() {
    local candidate
    for candidate in "${DB_USER}" "$(id -un)" postgres; do
        if PGPASSWORD="${DB_PASSWORD}" psql \
            -h "${DB_HOST}" \
            -p "${DB_PORT}" \
            -U "${candidate}" \
            -d postgres \
            -tAc "SELECT 1" >/dev/null 2>&1; then
            echo "${candidate}"
            return 0
        fi
    done
    return 1
}

reset_native_test_database() {
    local admin_user="$1"

    echo "Dropping test database if it exists..."
    PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${admin_user}" \
        -d postgres \
        -v ON_ERROR_STOP=1 \
        -c "DROP DATABASE IF EXISTS ${DB_NAME};"

    echo "Creating test database: ${DB_NAME}"
    PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${admin_user}" \
        -d postgres \
        -v ON_ERROR_STOP=1 \
        -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
}

ensure_supabase_compat_stubs() {
    # Local Postgres does not include Supabase's auth schema/functions.
    # Create a minimal auth.uid() shim so policy migrations compile.
    PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -v ON_ERROR_STOP=1 <<'SQL'
CREATE SCHEMA IF NOT EXISTS auth;

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
SQL
}

wait_for_docker_postgres() {
    local ready=false
    for _ in {1..30}; do
        if docker exec "${CONTAINER_NAME}" pg_isready -U "${DB_USER}" -d postgres >/dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 1
    done

    [[ "${ready}" == "true" ]]
}

setup_with_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi
    if ! docker compose -f "${COMPOSE_FILE}" ps "${SERVICE_NAME}" | grep -q "Up"; then
        echo "Starting Docker test Postgres service..."
        docker compose -f "${COMPOSE_FILE}" up -d "${SERVICE_NAME}"
    fi
    if ! wait_for_docker_postgres; then
        echo "ERROR: Docker PostgreSQL did not become ready in time"
        return 1
    fi

    echo "Dropping test database if it exists..."
    docker exec "${CONTAINER_NAME}" psql -h localhost -U "${DB_USER}" -d postgres \
        -c "DROP DATABASE IF EXISTS ${DB_NAME};" >/dev/null

    echo "Creating test database: ${DB_NAME}"
    docker exec "${CONTAINER_NAME}" psql -h localhost -U "${DB_USER}" -d postgres \
        -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" >/dev/null

    # Match local lane by ensuring auth.uid exists in dockerized vanilla Postgres too.
    docker exec "${CONTAINER_NAME}" psql -h localhost -U "${DB_USER}" -d "${DB_NAME}" \
        -c "CREATE SCHEMA IF NOT EXISTS auth;" >/dev/null
    docker exec "${CONTAINER_NAME}" psql -h localhost -U "${DB_USER}" -d "${DB_NAME}" \
        -c "CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS \$\$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid \$\$;" >/dev/null

    return 0
}

setup_mode="none"
if ensure_postgres_tools && wait_for_native_postgres; then
    admin_user="$(detect_native_admin_user || true)"
    if [[ -n "${admin_user:-}" ]]; then
        setup_mode="native"
        reset_native_test_database "${admin_user}"
        ensure_supabase_compat_stubs
    fi
fi

if [[ "${setup_mode}" == "none" ]]; then
    if setup_with_docker; then
        setup_mode="docker"
    else
        echo "ERROR: No usable test Postgres detected."
        echo "Expected native DB at ${TEST_DATABASE_URL}, or Docker service ${SERVICE_NAME}."
        echo "Native hint: run ./dev.sh start (or ensure local Postgres tools are in PATH)."
        echo "Docker fallback: docker compose -f ${COMPOSE_FILE} up -d ${SERVICE_NAME}"
        exit 1
    fi
fi

echo "Applying Alembic migrations to test database (${setup_mode} mode)..."
if command -v uv >/dev/null 2>&1; then
    (
        cd "${BACKEND_ROOT}"
        DATABASE_URL_DIRECT="${TEST_DATABASE_URL}" UV_NATIVE_TLS=1 uv run alembic -c api/alembic.ini upgrade head
    )
else
    (
        cd "${BACKEND_ROOT}"
        DATABASE_URL_DIRECT="${TEST_DATABASE_URL}" alembic -c api/alembic.ini upgrade head
    )
fi

echo "✓ Test database created and migrated successfully!"
echo ""
echo "You can now run tests with:"
echo "  pytest backend/tests/"
