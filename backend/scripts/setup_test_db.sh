#!/bin/bash
# Setup test database for running tests
# This script creates a separate PostgreSQL database for testing

set -e

echo "Setting up test database..."

# Database credentials (must match .env.test)
DB_USER="agent_smith"
DB_PASSWORD="agent_smith_dev"
DB_NAME="agent_smith_test"
CONTAINER_NAME="agent-smith-postgres-1"

# Check if PostgreSQL container is running
if ! docker compose ps postgres | grep -q "Up"; then
    echo "ERROR: PostgreSQL container is not running"
    echo "Start it with: docker compose up -d postgres"
    exit 1
fi

# Drop test database if it exists (clean slate)
echo "Dropping test database if it exists..."
docker exec $CONTAINER_NAME psql -U $DB_USER -d postgres \
    -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true

# Create test database
echo "Creating test database: $DB_NAME"
docker exec $CONTAINER_NAME psql -U $DB_USER -d postgres \
    -c "CREATE DATABASE $DB_NAME;"

echo "✓ Test database created successfully!"
echo ""
echo "You can now run tests with:"
echo "  pytest tests/"
echo ""
echo "To clean up the test database:"
echo "  docker exec $CONTAINER_NAME psql -U $DB_USER -d postgres -c 'DROP DATABASE $DB_NAME;'"
