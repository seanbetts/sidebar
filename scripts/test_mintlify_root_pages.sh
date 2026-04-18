#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - <<'PY' "${REPO_ROOT}"
import json
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
errors: list[str] = []

for docs_dir in (repo_root / "docs" / "product", repo_root / "docs" / "design"):
    config = json.loads((docs_dir / "docs.json").read_text())
    pages = [
        page
        for group in config.get("navigation", {}).get("groups", [])
        for page in group.get("pages", [])
    ]
    if "index" not in pages:
        errors.append(f"{docs_dir}/docs.json must include 'index' in navigation pages")

    if not any((docs_dir / f"index.{ext}").exists() for ext in ("md", "mdx")):
        errors.append(f"{docs_dir} must contain index.md or index.mdx")

if errors:
    for error in errors:
        print(error)
    sys.exit(1)
PY
