#!/bin/bash
set -euo pipefail

# run_tests_docker.sh - Run tests inside Docker container
# Usage:
#   ./scripts/run_tests_docker.sh           # Run all tests
#   ./scripts/run_tests_docker.sh -v        # Verbose output
#   ./scripts/run_tests_docker.sh tests/scripts/  # Run specific tests

echo "Running tests in Docker container..."

# Ensure skills-api container is running
if ! docker compose ps skills-api | grep -q "Up"; then
    echo "Starting Docker container..."
    docker compose up -d
fi

# Run pytest in skills-api container
docker compose exec skills-api pytest /app/api "$@"

echo "Tests complete!"
