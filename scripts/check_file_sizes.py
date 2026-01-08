#!/usr/bin/env python3
"""Check file size limits according to AGENTS.md standards."""

from __future__ import annotations

import sys
from pathlib import Path

LIMITS = {
    "backend/api/services": (400, 850),
    "backend/api/routers": (350, 850),
    "frontend/src/lib/components": (400, 850),
    "frontend/src/lib/stores": (400, 850),
}


def count_lines(file_path: Path) -> int:
    """Count non-empty lines in a file."""
    try:
        with file_path.open(encoding="utf-8") as handle:
            return sum(1 for line in handle if line.strip())
    except Exception:
        return 0


def check_file_sizes(file_paths: list[Path] | None = None) -> bool:
    """Check all files against size limits."""
    warnings: list[str] = []
    violations: list[str] = []

    if file_paths:
        candidates = file_paths
    else:
        candidates = []
        for directory in LIMITS:
            dir_path = Path(directory)
            if dir_path.exists():
                candidates.extend(
                    [
                        *dir_path.rglob("*.py"),
                        *dir_path.rglob("*.ts"),
                        *dir_path.rglob("*.svelte"),
                    ]
                )

    for file_path in candidates:
        if "node_modules" in str(file_path) or ".test." in file_path.name:
            continue

        for directory, (soft_limit, hard_limit) in LIMITS.items():
            dir_path = Path(directory)
            if dir_path in file_path.parents:
                lines = count_lines(file_path)
                if lines > hard_limit:
                    violations.append(
                        f"❌ {file_path}: {lines} LOC (hard limit: {hard_limit})"
                    )
                elif soft_limit and lines > soft_limit:
                    warnings.append(
                        f"⚠️  {file_path}: {lines} LOC (soft limit: {soft_limit})"
                    )
                break

    if warnings:
        print("\nFile Size Warnings:")
        for warning in warnings:
            print(warning)

    if violations:
        print("\nFile Size Violations (MUST FIX):")
        for violation in violations:
            print(violation)
        print("\nTip: See AGENTS.md for file splitting strategies")
        return False

    if not warnings:
        print("✅ All files within size limits")
    return True


if __name__ == "__main__":
    paths = [Path(arg) for arg in sys.argv[1:]]
    sys.exit(0 if check_file_sizes(paths or None) else 1)
