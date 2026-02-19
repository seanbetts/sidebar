#!/usr/bin/env python3
"""Fail if public Swift types in ViewModels/Services are missing doc comments."""

from __future__ import annotations

import re
import sys
from pathlib import Path

PUBLIC_TYPE_RE = re.compile(r"\bpublic\s+(final\s+)?(class|struct|enum|protocol)\b")
DOC_COMMENT_PREFIXES = ("///", "/**")


def has_doc_comment(lines: list[str], index: int) -> bool:
    """Return true when a Swift declaration line has a preceding doc comment."""
    cursor = index - 1
    while cursor >= 0:
        line = lines[cursor].strip()
        if not line:
            cursor -= 1
            continue
        return line.startswith(DOC_COMMENT_PREFIXES)
    return False


def iter_swift_files(root: Path) -> list[Path]:
    """Return sorted Swift source files under a root path."""
    if not root.exists():
        return []
    return sorted(path for path in root.rglob("*.swift") if path.is_file())


def emit(message: str = "") -> None:
    """Write one line to stdout."""
    sys.stdout.write(f"{message}\n")


def main() -> int:
    """Check required Swift folders and fail on missing doc comments."""
    repo_root = Path(__file__).resolve().parents[1]
    targets = [
        repo_root / "ios/sideBar/sideBar/ViewModels",
        repo_root / "ios/sideBar/sideBar/Services",
        repo_root / "ios/sideBar/sideBar/Stores",
    ]
    missing: list[str] = []

    for target in targets:
        for path in iter_swift_files(target):
            lines = path.read_text().splitlines()
            for index, line in enumerate(lines):
                if PUBLIC_TYPE_RE.search(line) and not has_doc_comment(lines, index):
                    missing.append(f"{path}:{index + 1}: {line.strip()}")

    if missing:
        emit("Missing doc comments for public Swift types:")
        for item in missing:
            emit(f"  {item}")
        return 1

    emit("Doc comment check passed for ViewModels/Services/Stores.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
