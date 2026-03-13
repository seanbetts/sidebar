#!/usr/bin/env python3
"""Resolve xcodebuild test specs from the committed Apple taxonomy manifest."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

TEST_CLASS_PATTERN = re.compile(
    r"(?:final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^{]+)\{",
)
EXTENSION_PATTERN = re.compile(r"extension\s+([A-Za-z_][A-Za-z0-9_]*)\b")


def load_manifest(path: Path) -> dict[str, object]:
    """Load the taxonomy manifest from disk."""
    return json.loads(path.read_text())


def target_from_manifest_path(path: str) -> str:
    """Infer the XCTest target name from a manifest path."""
    parts = Path(path).parts
    if len(parts) < 4:
        raise ValueError(f"Unsupported manifest path: {path}")
    return parts[2]


def target_for_selection(selection: str, path: str) -> str:
    """Return the XCTest target name for a resolver selection and manifest path."""
    if selection in {"dev_logic", "main_logic"}:
        return "sideBarLogicTests"
    return target_from_manifest_path(path)


def extract_test_class_names(path: Path) -> list[str]:
    """Return XCTestCase class names referenced by a Swift test source file."""
    text = path.read_text()
    if "func test" not in text:
        return []

    direct_matches = []
    for class_name, inheritance_clause in TEST_CLASS_PATTERN.findall(text):
        normalized_inheritance = inheritance_clause.strip()
        if (
            "XCTestCase" in normalized_inheritance
            or "TestCase" in normalized_inheritance
            or class_name.endswith("Tests")
        ):
            direct_matches.append(class_name)
    if direct_matches:
        return sorted(dict.fromkeys(direct_matches))

    extension_matches = EXTENSION_PATTERN.findall(text)
    return sorted(dict.fromkeys(extension_matches))


def _matching_rows(manifest: dict[str, object], selection: str) -> list[dict[str, str]]:
    """Return manifest rows for a named resolver selection."""
    rows = manifest["tests"]
    if selection == "dev_logic":
        return [row for row in rows if row["branch_policy"] == "dev"]
    if selection == "main_logic":
        return [row for row in rows if row["bucket"] == "logic"]
    if selection == "main_surface":
        return [
            row
            for row in rows
            if row["bucket"] == "surface"
            and row["path"].startswith("ios/sideBar/sideBarTests/")
        ]
    if selection == "main_extensions":
        return [
            row
            for row in rows
            if row["bucket"] == "surface"
            and row["path"].startswith("ios/sideBar/ShareExtensionTests/")
        ]
    if selection == "ui_smoke":
        return [row for row in rows if row["bucket"] == "ui_smoke"]
    raise ValueError(f"Unsupported selection: {selection}")


def resolve_selection_specs(
    manifest_path: Path,
    repo_root: Path,
    selection: str,
) -> list[str]:
    """Return sorted `xcodebuild -only-testing` specs for a named selection."""
    manifest = load_manifest(manifest_path)
    specs: set[str] = set()

    for row in _matching_rows(manifest, selection):
        source_path = repo_root / row["path"]
        if not source_path.exists():
            raise FileNotFoundError(f"Taxonomy source file missing: {source_path}")
        target = target_for_selection(selection, row["path"])
        class_names = extract_test_class_names(source_path)
        if not class_names:
            raise ValueError(
                f"Could not derive XCTestCase class names for taxonomy row: {row['path']}"
            )
        for class_name in class_names:
            specs.add(f"{target}/{class_name}")

    return sorted(specs)


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Resolve xcodebuild only-testing specs from the Apple taxonomy."
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("scripts/ios_test_taxonomy.json"),
        help="Path to the Apple taxonomy manifest.",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path("."),
        help="Repository root for manifest path resolution.",
    )
    parser.add_argument(
        "--selection",
        required=True,
        help="Named resolver selection such as dev_logic, main_surface, or ui_smoke.",
    )
    return parser.parse_args(argv)


def emit(message: str = "") -> None:
    """Write one line to stdout."""
    sys.stdout.write(f"{message}\n")


def main(argv: list[str] | None = None) -> int:
    """Resolve specs for one selection and print them as CSV."""
    args = parse_args(argv or sys.argv[1:])
    try:
        specs = resolve_selection_specs(
            manifest_path=args.manifest.resolve(),
            repo_root=args.repo_root.resolve(),
            selection=args.selection,
        )
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        emit(f"Resolution failed: {exc}")
        return 1

    emit(",".join(specs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
