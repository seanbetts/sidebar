#!/usr/bin/env python3
"""Enforce notes runtime and shell boundaries against legacy editor dependencies."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

RUNTIME_ROOT = Path("ios/sideBar/sideBar")
BACKEND_NOTES_ROOT = Path("backend")
NOTES_SHELL_RELATIVE_PATHS = (
    Path("ViewModels/NotesEditorViewModel.swift"),
    Path("Views/Notes/NotesView.swift"),
    Path("Views/Notes/NotesDetailView.swift"),
    Path("Views/Notes/NotesDetailView+MenuActions.swift"),
    Path("Views/Notes/NotesDetailView+FileOperations.swift"),
    Path("Views/Notes/AttributedNoteEditorContainer.swift"),
    Path("Views/Notes/ScratchpadPopoverView.swift"),
    Path("Views/Notes/SwiftUINoteTextEditorSurface.swift"),
    Path("Views/SidebarPanels/NotesPanel+ContextMenu.swift"),
)
NOTES_EDITOR_GLOB = "ViewModels/NativeNoteEditorViewModel*.swift"
NOTES_DEPENDENCY_RELATIVE_PATHS = (Path("Utilities/NoteTextDependencies.swift"),)
NOTES_RUNTIME_CLEANUP_RELATIVE_PATHS = (
    Path("Utilities/NotesRichTextCodec.swift"),
    Path("Utilities/NoteTextBridging.swift"),
    Path("ViewModels/NativeNoteEditorViewModel+Styling.swift"),
    Path("ViewModels/NoteFormatting.swift"),
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
    r"\bcopyMarkdown\b",
    r"^\s*import\s+MarkdownUI\b",
)
FORBIDDEN_NOTES_DEPENDENCY_PATTERNS = (
    r"\bMarkdownImporter\b",
    r"\bMarkdownImportResult\b",
    r"\bMarkdownEditorAttributes\b",
    r"\bSideBarMarkdownLayout\b",
    r"\bSideBarMarkdownStyle\b",
    r"\bMarkdownFormattingDefinition\b",
    r"\bMarkdownShortcutProcessor\b",
)
FORBIDDEN_NOTES_RUNTIME_CLEANUP_PATTERNS = (
    r"\bNoteFormattingCapability\b",
    r"\bruntimeCapability\b",
    r"\bplatformSystemFont\s*\(",
    r"\bplatformFontApplyingTraits\s*\(",
    r"\bswiftUIFontHasTrait\s*\(",
    r"\battributedNoteTextSurface\b",
)
BACKEND_NOTES_RUNTIME_RELATIVE_PATHS = (
    Path("api/models/note.py"),
    Path("api/services/notes_service.py"),
    Path("api/services/notes_write_contract.py"),
    Path("api/services/notes_workspace_service.py"),
    Path("skills/notes/scripts/save_note_document.py"),
    Path("skills/notes/scripts/read_note.py"),
)
FORBIDDEN_BACKEND_NOTES_RUNTIME_PATTERNS = (
    r"\bnotes_content_codec\b",
    r"\blegacy_content\b",
    r"\blegacy_content_format\b",
    r"\bcontent_format\b",
    r"\b(?:note|existing|created|updated|restored)\.content\b",
    r"\bcanonical\.content\b",
)


@dataclass(frozen=True)
class ContractRequirement:
    """Required contract assertions for core notes runtime files."""

    file_path: Path
    required_patterns: tuple[str, ...]


REQUIRED_NOTES_CONTRACTS = (
    ContractRequirement(
        file_path=Path("ViewModels/NotesEditorViewModel.swift"),
        required_patterns=(
            r"\bsyncFromNativeEditor\s*\(",
            r"\bsharedNativeEditor\s*\(",
        ),
    ),
    ContractRequirement(
        file_path=Path("ViewModels/NativeNoteEditorViewModel+Persistence.swift"),
        required_patterns=(
            r"\bstruct\s+PersistenceSnapshot\b",
            r"\bcanonicalContent\s*:\s*String\b",
            r"\bplainText\s*:\s*String\b",
        ),
    ),
    ContractRequirement(
        file_path=Path("Views/Notes/AttributedNoteEditorContainer.swift"),
        required_patterns=(
            r"@StateObject\s+private\s+var\s+nativeViewModel\s*:\s*NativeNoteEditorViewModel",
            r"StateObject\s*\(\s*wrappedValue:\s*editorViewModel\.sharedNativeEditor\s*\(\s*\)\s*\)",
            r"\battachNativeEditor\s*\(\s*nativeViewModel\s*\)",
            r"\bsyncFromNativeEditor\s*\(\s*nativeViewModel\s*\)",
        ),
    ),
    ContractRequirement(
        file_path=Path("Views/Notes/SwiftUINoteTextEditorSurface.swift"),
        required_patterns=(
            r"\bTextEditor\s*\(\s*text:\s*\$viewModel\.attributedContent\s*,\s*selection:\s*\$viewModel\.selection\s*\)",
            r"\.attributedTextFormattingDefinition\s*\(\s*NoteTextFormattingDefinition\s*\(\s*baseFontSize:\s*viewModel\.baseFontSize\s*\)\s*\)",
            r"\bviewModel\.handleContentChange\s*\(",
        ),
    ),
)


@dataclass(frozen=True)
class Violation:
    """One forbidden reference in a runtime boundary file."""

    file_path: Path
    line: int
    token: str


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
    """Return notes dependency files that should avoid markdown-named symbols."""
    root = repo_root / RUNTIME_ROOT
    files: list[Path] = []
    for relative_path in NOTES_DEPENDENCY_RELATIVE_PATHS:
        candidate = root / relative_path
        if candidate.exists() and candidate.is_file():
            files.append(candidate)
    return files


def _backend_notes_runtime_files(repo_root: Path) -> list[Path]:
    """Return backend notes runtime files that should avoid legacy note storage."""
    root = repo_root / BACKEND_NOTES_ROOT
    files: list[Path] = []
    for relative_path in BACKEND_NOTES_RUNTIME_RELATIVE_PATHS:
        candidate = root / relative_path
        if candidate.exists() and candidate.is_file():
            files.append(candidate)
    return files


def _notes_runtime_cleanup_files(repo_root: Path) -> list[Path]:
    """Return files that should no longer contain dead phase-5 cleanup leftovers."""
    root = repo_root / RUNTIME_ROOT
    files: list[Path] = []
    for relative_path in NOTES_RUNTIME_CLEANUP_RELATIVE_PATHS:
        candidate = root / relative_path
        if candidate.exists() and candidate.is_file():
            files.append(candidate)
    return files


def _check_contract_requirements(repo_root: Path) -> list[Violation]:
    """Return missing required notes runtime contract patterns."""
    root = repo_root / RUNTIME_ROOT
    violations: list[Violation] = []
    for requirement in REQUIRED_NOTES_CONTRACTS:
        candidate = root / requirement.file_path
        if not candidate.exists() or not candidate.is_file():
            violations.append(
                Violation(
                    file_path=candidate,
                    line=1,
                    token=f"missing required contract file {requirement.file_path}",
                )
            )
            continue
        source = candidate.read_text(encoding="utf-8")
        for required_pattern in requirement.required_patterns:
            compiled = re.compile(required_pattern, flags=re.MULTILINE)
            if compiled.search(source):
                continue
            violations.append(
                Violation(
                    file_path=candidate,
                    line=1,
                    token=f"missing required contract pattern {required_pattern}",
                )
            )
    return violations


def check(repo_root: Path) -> list[Violation]:
    """Run notes runtime boundary and contract checks and return violations."""
    notes_shell_files = _notes_shell_files(repo_root)
    notes_shell_compiled = tuple(
        re.compile(pattern) for pattern in FORBIDDEN_NOTES_SHELL_PATTERNS
    )
    notes_dependency_files = _notes_dependency_files(repo_root)
    notes_dependency_compiled = tuple(
        re.compile(pattern) for pattern in FORBIDDEN_NOTES_DEPENDENCY_PATTERNS
    )
    notes_runtime_cleanup_files = _notes_runtime_cleanup_files(repo_root)
    notes_runtime_cleanup_compiled = tuple(
        re.compile(pattern) for pattern in FORBIDDEN_NOTES_RUNTIME_CLEANUP_PATTERNS
    )
    backend_notes_runtime_files = _backend_notes_runtime_files(repo_root)
    backend_notes_runtime_compiled = tuple(
        re.compile(pattern) for pattern in FORBIDDEN_BACKEND_NOTES_RUNTIME_PATTERNS
    )
    violations: list[Violation] = _check_contract_requirements(repo_root)
    for file_path in notes_shell_files:
        violations.extend(_scan_file(file_path, notes_shell_compiled))
    for file_path in notes_dependency_files:
        violations.extend(_scan_file(file_path, notes_dependency_compiled))
    for file_path in notes_runtime_cleanup_files:
        violations.extend(_scan_file(file_path, notes_runtime_cleanup_compiled))
    for file_path in backend_notes_runtime_files:
        violations.extend(_scan_file(file_path, backend_notes_runtime_compiled))
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
        sys.stdout.write("Notes runtime boundary check passed.\n")
        return 0

    sys.stdout.write("Notes runtime boundary violations found:\n")
    for violation in violations:
        relative_path = violation.file_path.relative_to(repo_root)
        sys.stdout.write(
            f"  {relative_path}:{violation.line}: "
            f"forbidden reference {violation.token}\n"
        )
    return 1


if __name__ == "__main__":
    sys.exit(main())
