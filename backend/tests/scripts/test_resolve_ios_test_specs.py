"""Tests for Apple taxonomy-driven xcodebuild test spec resolution."""

from __future__ import annotations

import importlib.util
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = REPO_ROOT / "scripts" / "resolve_ios_test_specs.py"
MANIFEST_PATH = REPO_ROOT / "scripts" / "ios_test_taxonomy.json"


def _load_module():
    """Load the resolver module from disk."""
    assert MODULE_PATH.exists(), f"Missing resolver script: {MODULE_PATH}"
    module_spec = importlib.util.spec_from_file_location(
        "resolve_ios_test_specs",
        MODULE_PATH,
    )
    assert module_spec is not None and module_spec.loader is not None
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    return module


def test_resolver_script_exists() -> None:
    """The taxonomy resolver should be checked in."""
    assert MODULE_PATH.exists()


def test_extract_test_class_names_supports_primary_and_extension_files() -> None:
    """Resolver should derive XCTestCase class names from both file styles."""
    module = _load_module()

    direct_classes = module.extract_test_class_names(
        REPO_ROOT / "ios" / "sideBar" / "sideBarTests" / "ChatStreamParserTests.swift"
    )
    extension_classes = module.extract_test_class_names(
        REPO_ROOT
        / "ios"
        / "sideBar"
        / "sideBarTests"
        / "ChatViewModelTests+PromptPreview.swift"
    )

    assert direct_classes == ["ChatStreamParserTests"]
    assert extension_classes == ["ChatViewModelTests"]


def test_dev_logic_selection_returns_logic_specs_only() -> None:
    """The `dev_logic` selection should resolve only the logic layer."""
    module = _load_module()

    specs = module.resolve_selection_specs(
        manifest_path=MANIFEST_PATH,
        repo_root=REPO_ROOT,
        selection="dev_logic",
    )

    assert "sideBarTests/ChatStreamParserTests" in specs
    assert "sideBarTests/ContentViewLifecycleTests" not in specs
    assert "sideBarUITests/SideBarUITests" not in specs


def test_main_surface_selection_returns_sidebartests_surface_specs() -> None:
    """The `main_surface` selection should resolve app-surface classes only."""
    module = _load_module()

    specs = module.resolve_selection_specs(
        manifest_path=MANIFEST_PATH,
        repo_root=REPO_ROOT,
        selection="main_surface",
    )

    assert "sideBarTests/ContentViewLifecycleTests" in specs
    assert "sideBarTests/NotesEditorViewModelTests" in specs
    assert "sideBarTests/ChatStreamParserTests" not in specs
    assert all(spec.startswith("sideBarTests/") for spec in specs)


def test_ui_smoke_selection_deduplicates_shared_ui_test_classes() -> None:
    """UI support files should collapse onto the underlying XCTestCase classes."""
    module = _load_module()

    specs = module.resolve_selection_specs(
        manifest_path=MANIFEST_PATH,
        repo_root=REPO_ROOT,
        selection="ui_smoke",
    )

    assert specs == [
        "sideBarUITests/SideBarUITests",
        "sideBarUITests/SideBarUITestsLaunchTests",
    ]


def test_unknown_selection_fails_loudly() -> None:
    """Unknown resolver selections should fail instead of silently returning nothing."""
    module = _load_module()

    try:
        module.resolve_selection_specs(
            manifest_path=MANIFEST_PATH,
            repo_root=REPO_ROOT,
            selection="unknown_selection",
        )
    except ValueError as exc:
        assert "unknown_selection" in str(exc)
    else:  # pragma: no cover - defensive
        raise AssertionError("Expected ValueError for unknown selection")
