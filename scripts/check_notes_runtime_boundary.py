#!/usr/bin/env python3
"""Enforce NotesRuntime boundary against legacy markdown editor dependencies."""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


RUNTIME_ROOT = Path("ios/sideBar/sideBar")
SWIFT_GLOB = "*.swift"
FORBIDDEN_PATTERNS = (
    r"\bNativeMarkdownEditorViewModel\b",
    r"\bMarkdownEditorView\b",
    r"\bMarkdownCanonicalizer\b",
    r"\bMarkdownImporter\b",
    r"\bMarkdownExporter\b",
    r"\bMarkdownShortcutProcessor\b",
    r"\bMarkdownRendering\b",
)


@dataclass(frozen=True)
class Violation:
    """One forbidden reference in a runtime boundary file."""

    file_path: Path
    line: int
    token: str


def _runtime_boundary_files(repo_root: Path) -> list[Path]:
    """Return NotesRuntime boundary files that must avoid legacy dependencies."""
    root = repo_root / RUNTIME_ROOT
    if not root.exists():
        return []
    files: list[Path] = []
    for path in sorted(root.rglob(SWIFT_GLOB)):
        if not path.is_file():
            continue
        source = path.read_text(encoding="utf-8")
        if "NotesRuntime" in source or "notesRuntime" in source:
            files.append(path)
    return files


def _scan_file(path: Path, patterns: tuple[re.Pattern[str], ...]) -> list[Violation]:
    """Return all forbidden references for one file."""
    violations: list[Violation] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        for pattern in patterns:
            if pattern.search(line):
                violations.append(
                    Violation(file_path=path, line=line_number, token=pattern.pattern)
                )
    return violations


def check(repo_root: Path) -> list[Violation]:
    """Run NotesRuntime boundary checks and return violations."""
    runtime_files = _runtime_boundary_files(repo_root)
    compiled = tuple(re.compile(pattern) for pattern in FORBIDDEN_PATTERNS)
    violations: list[Violation] = []
    for file_path in runtime_files:
        violations.extend(_scan_file(file_path, compiled))
    return violations


def main() -> int:
    """Run check and return process exit code."""
    parser = argparse.ArgumentParser(
        description="Check NotesRuntime boundary for legacy markdown dependencies."
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root path.",
    )
    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    violations = check(repo_root)
    if not violations:
        print("Notes runtime boundary check passed.")
        return 0

    print("Notes runtime boundary violations found:")
    for violation in violations:
        relative_path = violation.file_path.relative_to(repo_root)
        print(f"  {relative_path}:{violation.line}: forbidden reference {violation.token}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
