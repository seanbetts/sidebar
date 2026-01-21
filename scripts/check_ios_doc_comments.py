#!/usr/bin/env python3
"""Fail if public Swift types in ViewModels/Services are missing doc comments."""
from __future__ import annotations

from pathlib import Path
import re
import sys


PUBLIC_TYPE_RE = re.compile(r"\bpublic\s+(final\s+)?(class|struct|enum|protocol)\b")
DOC_COMMENT_PREFIXES = ("///", "/**")


def has_doc_comment(lines: list[str], index: int) -> bool:
    cursor = index - 1
    while cursor >= 0:
        line = lines[cursor].strip()
        if not line:
            cursor -= 1
            continue
        return line.startswith(DOC_COMMENT_PREFIXES)
    return False


def iter_swift_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted(path for path in root.rglob("*.swift") if path.is_file())


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    targets = [
        repo_root / "ios/sideBar/sideBar/ViewModels",
        repo_root / "ios/sideBar/sideBar/Services",
    ]
    missing: list[str] = []

    for target in targets:
        for path in iter_swift_files(target):
            lines = path.read_text().splitlines()
            for index, line in enumerate(lines):
                if PUBLIC_TYPE_RE.search(line):
                    if not has_doc_comment(lines, index):
                        missing.append(f"{path}:{index + 1}: {line.strip()}")

    if missing:
        print("Missing doc comments for public Swift types:")
        for item in missing:
            print(f"  {item}")
        return 1

    print("Doc comment check passed for ViewModels/Services.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
