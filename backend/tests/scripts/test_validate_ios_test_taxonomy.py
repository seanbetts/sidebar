"""Tests for the Apple test taxonomy manifest and validator."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
MANIFEST_PATH = REPO_ROOT / "scripts" / "ios_test_taxonomy.json"
MODULE_PATH = REPO_ROOT / "scripts" / "validate_ios_test_taxonomy.py"
APPLE_TEST_DIRS = (
    REPO_ROOT / "ios" / "sideBar" / "sideBarTests",
    REPO_ROOT / "ios" / "sideBar" / "ShareExtensionTests",
    REPO_ROOT / "ios" / "sideBar" / "sideBarUITests",
)
ALLOWED_BUCKETS = {"logic", "surface", "ui_smoke"}
ALLOWED_BRANCH_POLICIES = {"dev", "main", "manual_only"}


def _load_validator_module():
    """Load the committed taxonomy validator module."""
    assert MODULE_PATH.exists(), f"Missing validator script: {MODULE_PATH}"
    module_spec = importlib.util.spec_from_file_location(
        "validate_ios_test_taxonomy",
        MODULE_PATH,
    )
    assert module_spec is not None and module_spec.loader is not None
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    return module


def _load_manifest() -> dict[str, object]:
    """Load the committed Apple taxonomy manifest."""
    assert MANIFEST_PATH.exists(), f"Missing taxonomy manifest: {MANIFEST_PATH}"
    return json.loads(MANIFEST_PATH.read_text())


def _discover_apple_swift_files() -> set[str]:
    """Return every Swift file that lives inside Apple test directories."""
    paths: set[str] = set()
    for root in APPLE_TEST_DIRS:
        paths.update(
            str(path.relative_to(REPO_ROOT))
            for path in sorted(root.rglob("*.swift"))
            if path.is_file()
        )
    return paths


def test_taxonomy_manifest_and_validator_exist() -> None:
    """The taxonomy reset should commit both the manifest and its validator."""
    assert MANIFEST_PATH.exists()
    assert MODULE_PATH.exists()


def test_taxonomy_manifest_accounts_for_all_apple_swift_files() -> None:
    """Every Apple-side Swift test/support file should be accounted for exactly once."""
    manifest = _load_manifest()
    classified_paths = {entry["path"] for entry in manifest["tests"]}
    excluded_paths = {entry["path"] for entry in manifest["excluded_files"]}

    assert classified_paths.isdisjoint(excluded_paths)
    assert classified_paths | excluded_paths == _discover_apple_swift_files()


def test_taxonomy_manifest_entries_use_supported_values() -> None:
    """Committed taxonomy rows should use only supported bucket and branch values."""
    manifest = _load_manifest()

    for entry in manifest["tests"]:
        assert entry["bucket"] in ALLOWED_BUCKETS
        assert entry["branch_policy"] in ALLOWED_BRANCH_POLICIES
        assert entry["feature_area"]


def test_validator_accepts_the_committed_manifest() -> None:
    """The committed validator should accept the committed manifest."""
    module = _load_validator_module()
    errors = module.validate_manifest(
        _load_manifest(),
        _discover_apple_swift_files(),
    )

    assert errors == []


def test_validator_rejects_ui_smoke_outside_ui_test_directory() -> None:
    """`ui_smoke` rows should be limited to the UI test target."""
    module = _load_validator_module()
    manifest = {
        "version": 1,
        "tests": [
            {
                "path": "ios/sideBar/sideBarTests/APIClientTests.swift",
                "bucket": "ui_smoke",
                "feature_area": "app_shell",
                "branch_policy": "main",
            }
        ],
        "excluded_files": [],
    }
    errors = module.validate_manifest(
        manifest,
        {"ios/sideBar/sideBarTests/APIClientTests.swift"},
    )

    assert any("ui_smoke" in error for error in errors)


def test_validator_rejects_dev_entries_outside_logic_bucket() -> None:
    """Only logic tests should be eligible for the `dev` branch policy."""
    module = _load_validator_module()
    manifest = {
        "version": 1,
        "tests": [
            {
                "path": "ios/sideBar/sideBarTests/ContentViewLifecycleTests.swift",
                "bucket": "surface",
                "feature_area": "app_shell",
                "branch_policy": "dev",
            }
        ],
        "excluded_files": [],
    }
    errors = module.validate_manifest(
        manifest,
        {"ios/sideBar/sideBarTests/ContentViewLifecycleTests.swift"},
    )

    assert any("dev" in error for error in errors)
