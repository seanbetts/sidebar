#!/usr/bin/env python3
"""Validate the committed Apple test taxonomy manifest."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

APPLE_TEST_DIRS = (
    Path("ios/sideBar/sideBarTests"),
    Path("ios/sideBar/ShareExtensionTests"),
    Path("ios/sideBar/sideBarUITests"),
)
UI_TEST_DIR = "ios/sideBar/sideBarUITests/"
ALLOWED_BUCKETS = {"logic", "surface", "ui_smoke"}
ALLOWED_BRANCH_POLICIES = {"dev", "main", "manual_only"}


def discover_apple_swift_files(repo_root: Path) -> set[str]:
    """Return all Swift files under the Apple test directories."""
    paths: set[str] = set()
    for relative_root in APPLE_TEST_DIRS:
        root = repo_root / relative_root
        for path in sorted(root.rglob("*.swift")):
            if path.is_file():
                paths.add(str(path.relative_to(repo_root)))
    return paths


def load_manifest(path: Path) -> dict[str, object]:
    """Load a taxonomy manifest from disk."""
    return json.loads(path.read_text())


def _coerce_rows(
    manifest: dict[str, object],
    key: str,
    errors: list[str],
) -> list[dict[str, object]]:
    """Return manifest rows for a key or record a validation error."""
    value = manifest.get(key)
    if not isinstance(value, list):
        errors.append(f"Manifest key '{key}' must be a list.")
        return []
    rows: list[dict[str, object]] = []
    for index, entry in enumerate(value):
        if not isinstance(entry, dict):
            errors.append(f"Manifest key '{key}' entry {index} must be an object.")
            continue
        rows.append(entry)
    return rows


def validate_manifest(
    manifest: dict[str, object],
    discovered_paths: set[str],
) -> list[str]:
    """Return manifest validation errors."""
    errors: list[str] = []

    if manifest.get("version") != 1:
        errors.append("Manifest version must be 1.")

    test_rows = _coerce_rows(manifest, "tests", errors)
    excluded_rows = _coerce_rows(manifest, "excluded_files", errors)

    seen_paths: dict[str, str] = {}
    classified_paths: set[str] = set()
    excluded_paths: set[str] = set()

    for row in test_rows:
        path = row.get("path")
        bucket = row.get("bucket")
        feature_area = row.get("feature_area")
        branch_policy = row.get("branch_policy")

        if not isinstance(path, str) or not path:
            errors.append("Each test row must define a non-empty 'path'.")
            continue
        if path in seen_paths:
            errors.append(f"Duplicate manifest path entry: {path}")
            continue
        seen_paths[path] = "tests"
        classified_paths.add(path)

        if bucket not in ALLOWED_BUCKETS:
            errors.append(f"Unsupported bucket for {path}: {bucket!r}")
        if branch_policy not in ALLOWED_BRANCH_POLICIES:
            errors.append(f"Unsupported branch_policy for {path}: {branch_policy!r}")
        if not isinstance(feature_area, str) or not feature_area.strip():
            errors.append(f"Missing feature_area for {path}")
        if bucket == "ui_smoke" and not path.startswith(UI_TEST_DIR):
            errors.append(f"ui_smoke rows must live in {UI_TEST_DIR}: {path}")
        if branch_policy == "dev" and bucket != "logic":
            errors.append(f"Only logic rows may use branch_policy=dev: {path}")

    for row in excluded_rows:
        path = row.get("path")
        reason = row.get("reason")

        if not isinstance(path, str) or not path:
            errors.append("Each excluded_files row must define a non-empty 'path'.")
            continue
        if path in seen_paths:
            errors.append(f"Duplicate manifest path entry: {path}")
            continue
        seen_paths[path] = "excluded_files"
        excluded_paths.add(path)

        if not isinstance(reason, str) or not reason.strip():
            errors.append(f"Excluded file is missing a reason: {path}")

    accounted_paths = classified_paths | excluded_paths
    missing_paths = sorted(discovered_paths - accounted_paths)
    unexpected_paths = sorted(accounted_paths - discovered_paths)

    if missing_paths:
        errors.append(
            "Manifest is missing Apple Swift files: " + ", ".join(missing_paths)
        )
    if unexpected_paths:
        errors.append(
            "Manifest includes unknown Apple Swift files: "
            + ", ".join(unexpected_paths)
        )

    return errors


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Validate the committed Apple test taxonomy manifest."
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path("."),
        help="Repository root used for Apple test discovery.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("scripts/ios_test_taxonomy.json"),
        help="Path to the Apple taxonomy manifest.",
    )
    return parser.parse_args(argv)


def emit(message: str = "") -> None:
    """Write one line to stdout."""
    sys.stdout.write(f"{message}\n")


def main(argv: list[str] | None = None) -> int:
    """Validate the committed manifest and return a process exit code."""
    args = parse_args(argv or sys.argv[1:])
    repo_root = args.repo_root.resolve()
    manifest_path = args.manifest.resolve()

    try:
        manifest = load_manifest(manifest_path)
    except FileNotFoundError:
        emit(f"Validation failed: manifest not found at {manifest_path}")
        return 1
    except json.JSONDecodeError as exc:
        emit(f"Validation failed: manifest JSON is invalid: {exc}")
        return 1

    errors = validate_manifest(manifest, discover_apple_swift_files(repo_root))
    if errors:
        emit("Apple taxonomy validation failed:")
        for error in errors:
            emit(f"- {error}")
        return 1

    emit("Apple taxonomy validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
