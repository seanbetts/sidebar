#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_SH="${REPO_ROOT}/dev.sh"

python3 - <<'PY' "${DEV_SH}"
import re
import sys
from pathlib import Path

dev_sh = Path(sys.argv[1]).read_text()

required_vars = {
    "PRODUCT_DOCS_MINTLIFY_HOME": r'PRODUCT_DOCS_MINTLIFY_HOME="[^"]+"',
    "DESIGN_DOCS_MINTLIFY_HOME": r'DESIGN_DOCS_MINTLIFY_HOME="[^"]+"',
}

for name, pattern in required_vars.items():
    if re.search(pattern, dev_sh) is None:
        print(f"Missing {name} in dev.sh")
        sys.exit(1)

if "mintlify dev --port 3001 --no-open" not in dev_sh:
    print("Docs Mintlify launch must include --no-open on port 3001")
    sys.exit(1)

if "mintlify dev --port 3002 --no-open" not in dev_sh:
    print("Design docs Mintlify launch must include --no-open on port 3002")
    sys.exit(1)

if 'HOME="${PRODUCT_DOCS_MINTLIFY_HOME}" mintlify dev --port 3001 --no-open' not in dev_sh:
    print("Docs Mintlify launch must use PRODUCT_DOCS_MINTLIFY_HOME")
    sys.exit(1)

if 'HOME="${DESIGN_DOCS_MINTLIFY_HOME}" mintlify dev --port 3002 --no-open' not in dev_sh:
    print("Design docs Mintlify launch must use DESIGN_DOCS_MINTLIFY_HOME")
    sys.exit(1)
PY
