#!/bin/bash
# Run backend tests with required test database setup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
COMPOSE_FILE="${REPO_ROOT}/docker-compose.test.yml"
SERVICE_NAME="postgres-test"

if ! docker compose -f "$COMPOSE_FILE" ps "$SERVICE_NAME" >/dev/null 2>&1; then
  echo "ERROR: docker compose is not available or compose file missing."
  exit 1
fi

echo "Starting test database..."
docker compose -f "$COMPOSE_FILE" up -d "$SERVICE_NAME"

echo "Preparing test database..."
"${SCRIPT_DIR}/setup_test_db.sh"

echo "Running backend tests..."
cd "${REPO_ROOT}/backend"
uv run pytest

if [[ "${CLEANUP_TEST_DB:-0}" == "1" ]]; then
  echo "Stopping test database..."
  docker compose -f "$COMPOSE_FILE" down
fi
