"""Tests for scripts/check_notes_runtime_boundary.py."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "check_notes_runtime_boundary.py"
MODULE_SPEC = importlib.util.spec_from_file_location(
    "check_notes_runtime_boundary", MODULE_PATH
)
assert MODULE_SPEC is not None and MODULE_SPEC.loader is not None
BOUNDARY_MODULE = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = BOUNDARY_MODULE
MODULE_SPEC.loader.exec_module(BOUNDARY_MODULE)

check = BOUNDARY_MODULE.check


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def test_check_reports_runtime_boundary_forbidden_references(tmp_path: Path) -> None:
    """Runtime boundary files should fail when legacy editor symbols appear."""
    runtime_file = (
        tmp_path / "ios/sideBar/sideBar/App/NotesRuntime.swift"
    )
    _write(
        runtime_file,
        """
        import Foundation
        public final class NotesRuntime {
            let notesRuntime = "ready"
            let legacy = NativeMarkdownEditorViewModel()
        }
        """,
    )

    violations = check(tmp_path)

    assert any("NativeMarkdownEditorViewModel" in violation.token for violation in violations)


def test_check_reports_notes_shell_forbidden_references(tmp_path: Path) -> None:
    """Core notes shell files should fail if removed legacy symbols are reintroduced."""
    shell_file = (
        tmp_path / "ios/sideBar/sideBar/Views/Notes/NotesDetailView.swift"
    )
    _write(
        shell_file,
        """
        import SwiftUI
        struct NotesDetailView: View {
            var body: some View {
                SideBarMarkdownContainer(markdown: "legacy")
            }
        }
        """,
    )

    violations = check(tmp_path)

    assert any("SideBarMarkdownContainer" in violation.token for violation in violations)


def test_check_reports_markdown_method_calls_in_notes_runtime_files(
    tmp_path: Path,
) -> None:
    """Active notes runtime files should fail if markdown-named bridge methods are used."""
    runtime_callsite = (
        tmp_path / "ios/sideBar/sideBar/ViewModels/NotesEditorViewModel.swift"
    )
    _write(
        runtime_callsite,
        """
        import Foundation
        final class NotesEditorViewModel {
            func sync(vm: NativeMarkdownEditorViewModel) {
                vm.loadMarkdown("body")
                vm.markSaved(markdown: "body")
            }
        }
        """,
    )

    violations = check(tmp_path)

    assert any(
        "NativeMarkdownEditorViewModel" in violation.token for violation in violations
    )
    assert any("loadMarkdown" in violation.token for violation in violations)
    assert any("markSaved" in violation.token for violation in violations)


def test_check_passes_without_forbidden_references(tmp_path: Path) -> None:
    """No violations should be reported for clean runtime and shell files."""
    _write(
        tmp_path / "ios/sideBar/sideBar/App/NotesRuntime.swift",
        """
        import Foundation
        public final class NotesRuntime {
            let notesRuntime = "ready"
        }
        """,
    )
    _write(
        tmp_path / "ios/sideBar/sideBar/Views/Notes/NotesView.swift",
        """
        import SwiftUI
        struct NotesView: View {
            var body: some View { Text("Notes") }
        }
        """,
    )

    assert check(tmp_path) == []
