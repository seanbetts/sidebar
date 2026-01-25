#!/bin/bash
set -euo pipefail

TARGET="${1:-all}"

run_backend() {
  echo "Running backend tests..."
  (cd backend && ./scripts/run_tests.sh)
}

run_frontend() {
  echo "Running frontend tests..."
  (cd frontend && npm run test)
}

run_ios() {
  echo "Running iOS tests..."
  ./scripts/test-ios.sh
}

case "${TARGET}" in
  backend)
    run_backend
    ;;
  frontend)
    run_frontend
    ;;
  ios)
    run_ios
    ;;
  all)
    run_backend
    run_frontend
    ;;
  *)
    echo "Usage: ./scripts/test.sh [backend|frontend|ios|all]"
    exit 1
    ;;
esac
