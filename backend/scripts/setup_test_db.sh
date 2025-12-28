#!/bin/bash
# Setup test database for running tests
# This script creates a separate PostgreSQL database for testing

set -e

echo "Setting up test database..."

# Database credentials (must match .env.test)
DB_USER="sidebar"
DB_PASSWORD="sidebar_dev"
DB_NAME="sidebar_test"
CONTAINER_NAME="sidebar-test-postgres"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/../../docker-compose.test.yml"
SERVICE_NAME="postgres-test"

# Check if PostgreSQL container is running
if ! docker compose -f $COMPOSE_FILE ps $SERVICE_NAME | grep -q "Up"; then
    echo "ERROR: PostgreSQL container is not running"
    echo "Start it with: docker compose -f $COMPOSE_FILE up -d $SERVICE_NAME"
    exit 1
fi

# Wait for PostgreSQL to accept connections
echo "Waiting for PostgreSQL to be ready..."
ready=false
for i in {1..30}; do
    if docker exec $CONTAINER_NAME pg_isready -U $DB_USER -d postgres >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 1
done

if [ "$ready" != "true" ]; then
    echo "ERROR: PostgreSQL did not become ready in time"
    exit 1
fi

# Drop test database if it exists (clean slate)
echo "Dropping test database if it exists..."
docker exec $CONTAINER_NAME psql -h localhost -U $DB_USER -d postgres \
    -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true

# Create test database
echo "Creating test database: $DB_NAME"
docker exec $CONTAINER_NAME psql -h localhost -U $DB_USER -d postgres \
    -c "CREATE DATABASE $DB_NAME;"

echo "✓ Test database created successfully!"
echo ""
echo "You can now run tests with:"
echo "  pytest tests/"
echo ""
echo "To clean up the test database:"
echo "  docker exec $CONTAINER_NAME psql -U $DB_USER -d postgres -c 'DROP DATABASE $DB_NAME;'"
