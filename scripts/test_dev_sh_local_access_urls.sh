#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_SH="${REPO_ROOT}/dev.sh"

eval "$(
  awk '
    /^command="\$\{1:-start\}"$/ { exit }
    { print }
  ' "${DEV_SH}"
)"

output="$(print_local_access_urls)"

for expected in \
  "App website: http://app.trysidebar.localhost:8080" \
  "App website (direct): http://localhost:3000" \
  "Marketing website: http://trysidebar.localhost:8080" \
  "Marketing website (direct): http://localhost:5173"
do
  if [[ "${output}" != *"${expected}"* ]]; then
    echo "Missing local access URL in print_local_access_urls output: ${expected}"
    exit 1
  fi
done

python3 - <<'PY' "${DEV_SH}"
import re
import sys
from pathlib import Path

dev_sh = Path(sys.argv[1]).read_text()

for command in ("start", "restart", "status"):
    match = re.search(rf"^  {command}\)(.*?)^    ;;$", dev_sh, re.MULTILINE | re.DOTALL)
    if match is None:
        print(f"Missing {command} case in dev.sh")
        sys.exit(1)

    block = match.group(1)
    if "print_local_access_urls" not in block:
        print(f"{command} should print local access URLs")
        sys.exit(1)
PY
