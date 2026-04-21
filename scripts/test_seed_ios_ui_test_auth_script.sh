#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${REPO_ROOT}/scripts/seed_ios_ui_test_auth.sh"

python3 - <<'PY' "${SCRIPT_PATH}"
import sys
from pathlib import Path

contents = Path(sys.argv[1]).read_text()

required_snippets = [
    ".env.local",
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SIDEBAR_UI_TEST_ACCESS_TOKEN",
    "SIDEBAR_UI_TEST_USER_ID",
    "SIDEBAR_UI_TEST_USE_IN_MEMORY_AUTH=1",
    "/auth/v1/token?grant_type=password",
]

for snippet in required_snippets:
    if snippet not in contents:
        print(f"Missing required script snippet: {snippet}")
        sys.exit(1)
PY
