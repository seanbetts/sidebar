#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$(
  cd "${REPO_ROOT}"
  SIDEBAR_DEV_TEST_DB=0 ./dev.sh status
)"

grep -q "Design docs" <<<"${output}"
