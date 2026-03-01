#!/usr/bin/env python3
"""Enforce NotesRuntime and notes shell boundaries against legacy editor dependencies."""
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
NOTES_SHELL_RELATIVE_PATHS = (
    Path("ViewModels/NotesEditorViewModel.swift"),
    Path("ViewModels/AttributedNoteFormattingCommands.swift"),
    Path("ViewModels/AttributedNoteListCommands.swift"),
    Path("Views/Notes/NotesView.swift"),
    Path("Views/Notes/NotesDetailView.swift"),
    Path("Views/Notes/NotesDetailView+MenuActions.swift"),
    Path("Views/Notes/NotesDetailView+FileOperations.swift"),
    Path("Views/Notes/AttributedNoteEditorContainer.swift"),
    Path("Views/Notes/AttributedNoteEditorView.swift"),
    Path("Views/Notes/AttributedNoteKeyboardShortcuts.swift"),
)
NOTES_EDITOR_GLOB = "ViewModels/NativeNoteEditorViewModel*.swift"
NOTES_DEPENDENCY_RELATIVE_PATHS = (
    Path("Utilities/NoteTextDependencies.swift"),
)
FORBIDDEN_NOTES_SHELL_PATTERNS = (
    r"\bNativeMarkdownEditorViewModel\b",
    r"\bMarkdownFormatting\b",
    r"\bSideBarMarkdownContainer\b",
    r"\bMarkdownEditorView\b",
    r"\buseAttributedNoteEditorV2\b",
    r"\bloadMarkdown\s*\(",
    r"\bmarkSaved\s*\(\s*markdown\s*:",
    r"\bcurrentSerializedContent\s*\(",
    r"\bMarkdownImporter\b",
    r"\bMarkdownExporter\b",
    r"\bMarkdownShortcutProcessor\b",
    r"\bMarkdownFormattingDefinition\b",
    r"\bMarkdownTypography\b",
    r"\bMarkdownLineInference\b",
    r"\bMarkdownParagraphMetrics\b",
    r"\bMarkdownHeadingMetrics\b",
    r"\bSideBarMarkdownStyle\b",
    r"\bMarkdownEditorAttributes\b",
    r"\bSideBarMarkdownLayout\b",
)
FORBIDDEN_NOTES_DEPENDENCY_PATTERNS = (
    r"\bMarkdownEditorAttributes\b",
    r"\bSideBarMarkdownLayout\b",
    r"\bSideBarMarkdownStyle\b",
    r"\bMarkdownFormattingDefinition\b",
    r"\bMarkdownShortcutProcessor\b",
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


def _notes_shell_files(repo_root: Path) -> list[Path]:
    """Return notes shell files that should not reintroduce removed legacy symbols."""
    root = repo_root / RUNTIME_ROOT
    files: list[Path] = []
    for relative_path in NOTES_SHELL_RELATIVE_PATHS:
        candidate = root / relative_path
        if candidate.exists() and candidate.is_file():
            files.append(candidate)
    for candidate in sorted(root.glob(NOTES_EDITOR_GLOB)):
        if candidate.exists() and candidate.is_file():
            files.append(candidate)
    return files


def _notes_dependency_files(repo_root: Path) -> list[Path]:
    """Return notes dependency files that should avoid markdown-named layout/style/attribute symbols."""
    root = repo_root / RUNTIME_ROOT
    files: list[Path] = []
    for relative_path in NOTES_DEPENDENCY_RELATIVE_PATHS:
        candidate = root / relative_path
        if candidate.exists() and candidate.is_file():
            files.append(candidate)
    return files


def check(repo_root: Path) -> list[Violation]:
    """Run NotesRuntime boundary checks and return violations."""
    runtime_files = _runtime_boundary_files(repo_root)
    runtime_compiled = tuple(re.compile(pattern) for pattern in FORBIDDEN_PATTERNS)
    notes_shell_files = _notes_shell_files(repo_root)
    notes_shell_compiled = tuple(
        re.compile(pattern) for pattern in FORBIDDEN_NOTES_SHELL_PATTERNS
    )
    notes_dependency_files = _notes_dependency_files(repo_root)
    notes_dependency_compiled = tuple(
        re.compile(pattern) for pattern in FORBIDDEN_NOTES_DEPENDENCY_PATTERNS
    )
    violations: list[Violation] = []
    for file_path in runtime_files:
        violations.extend(_scan_file(file_path, runtime_compiled))
    for file_path in notes_shell_files:
        violations.extend(_scan_file(file_path, notes_shell_compiled))
    for file_path in notes_dependency_files:
        violations.extend(_scan_file(file_path, notes_dependency_compiled))
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
