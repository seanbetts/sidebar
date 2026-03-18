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
  echo "Running iOS logic tests..."
  xcodebuild test \
    -project ios/sideBar/sideBar.xcodeproj \
    -scheme sideBarLogicHost \
    -testPlan AppleFast \
    -destination 'platform=macOS' \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=
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
