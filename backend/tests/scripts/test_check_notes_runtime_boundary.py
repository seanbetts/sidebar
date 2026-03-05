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
        tmp_path / "ios/sideBar/sideBar/ViewModels/NotesEditorViewModel.swift"
    )
    _write(
        runtime_file,
        """
        import Foundation
        public final class NotesEditorViewModel {
            let legacy = NativeMarkdownEditorViewModel()
            func currentPersistenceSnapshot() {}
            func syncFromNativeEditor() {}
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


def test_check_reports_notes_shell_markdown_layout_and_attribute_references(
    tmp_path: Path,
) -> None:
    """Notes shell files should fail if markdown layout/attribute symbols are referenced directly."""
    editor_shell_file = (
        tmp_path / "ios/sideBar/sideBar/Views/Notes/SwiftUINoteTextEditorSurface.swift"
    )
    _write(
        editor_shell_file,
        """
        import SwiftUI
        extension AttributeScopes {
            struct NotesShellAttributes: AttributeScope {
                let markdownEditor: MarkdownEditorAttributes
            }
        }
        struct SwiftUINoteTextEditorSurface: View {
            @ObservedObject var viewModel: NativeNoteEditorViewModel
            var body: some View {
                TextEditor(text: $viewModel.attributedContent, selection: $viewModel.selection)
                    .attributedTextFormattingDefinition(NoteTextFormattingDefinition())
                    .onChange(of: viewModel.attributedContent) { previous, _ in
                        viewModel.handleContentChange(previous: previous)
                    }
                    .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
            }
        }
        """,
    )

    violations = check(tmp_path)

    assert any("MarkdownEditorAttributes" in violation.token for violation in violations)
    assert any("SideBarMarkdownLayout" in violation.token for violation in violations)


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
                let formatting: MarkdownFormatting = .bold
                _ = formatting
                vm.loadMarkdown("body")
                vm.markSaved(markdown: "body")
                _ = vm.currentSerializedContent()
            }
        }
        """,
    )
    _write(
        tmp_path / "ios/sideBar/sideBar/ViewModels/AttributedNoteListCommands.swift",
        """
        import Foundation
        enum AttributedNoteListCommands {
            static func indent(on viewModel: NativeMarkdownEditorViewModel) {}
        }
        """,
    )

    violations = check(tmp_path)

    assert any(
        "NativeMarkdownEditorViewModel" in violation.token for violation in violations
    )
    assert any("MarkdownFormatting" in violation.token for violation in violations)
    assert any("loadMarkdown" in violation.token for violation in violations)
    assert any("markSaved" in violation.token for violation in violations)
    assert any("currentSerializedContent" in violation.token for violation in violations)


def test_check_reports_direct_markdown_utility_references_in_native_note_editor(
    tmp_path: Path,
) -> None:
    """Native notes editor files should not directly reference markdown utility symbols."""
    editor_file = (
        tmp_path / "ios/sideBar/sideBar/ViewModels/NativeNoteEditorViewModel.swift"
    )
    _write(
        editor_file,
        """
        import Foundation
        final class NativeNoteEditorViewModel {
            let importer = MarkdownImporter()
            let exporter = MarkdownExporter()
            let style = SideBarMarkdownStyle.default

            func process() {
                _ = MarkdownShortcutProcessor.processShortcuts
                _ = MarkdownFormattingDefinition()
                _ = MarkdownTypography.defaultBodyFontSize
                _ = MarkdownLineInference.inferBlockKind(from: "x")
                _ = MarkdownParagraphMetrics.blockquoteIndentEm
                _ = MarkdownHeadingMetrics.isBold(level: 2)
            }
        }
        """,
    )

    violations = check(tmp_path)

    assert any("MarkdownImporter" in violation.token for violation in violations)
    assert any("MarkdownExporter" in violation.token for violation in violations)
    assert any("SideBarMarkdownStyle" in violation.token for violation in violations)
    assert any("MarkdownShortcutProcessor" in violation.token for violation in violations)
    assert any("MarkdownFormattingDefinition" in violation.token for violation in violations)
    assert any("MarkdownTypography" in violation.token for violation in violations)
    assert any("MarkdownLineInference" in violation.token for violation in violations)
    assert any("MarkdownParagraphMetrics" in violation.token for violation in violations)
    assert any("MarkdownHeadingMetrics" in violation.token for violation in violations)


def test_check_reports_markdown_layout_style_attribute_references_in_note_dependencies(
    tmp_path: Path,
) -> None:
    """Notes dependency wrappers should fail if markdown utility/layout/style/attribute symbols are referenced."""
    dependencies_file = (
        tmp_path / "ios/sideBar/sideBar/Utilities/NoteTextDependencies.swift"
    )
    _write(
        dependencies_file,
        """
        import SwiftUI
        typealias NoteTextEditorAttributes = AttributeScopes.MarkdownEditorAttributes
        enum NoteTextLayout {
            static let maxContentWidth: CGFloat = SideBarMarkdownLayout.maxContentWidth
        }
        struct NoteTextStyle {
            static let `default` = SideBarMarkdownStyle.default
        }
        struct NoteTextFormattingDefinition {
            let definition = MarkdownFormattingDefinition()
        }
        struct NoteTextShortcutProcessor {
            static func process() {
                _ = MarkdownShortcutProcessor.processShortcuts
            }
        }
        struct NoteTextImporter {
            let importer = MarkdownImporter()
            let resultType: MarkdownImportResult.Type? = nil
        }
        """,
    )

    violations = check(tmp_path)

    assert any("MarkdownImporter" in violation.token for violation in violations)
    assert any("MarkdownImportResult" in violation.token for violation in violations)
    assert any("MarkdownEditorAttributes" in violation.token for violation in violations)
    assert any("SideBarMarkdownLayout" in violation.token for violation in violations)
    assert any("SideBarMarkdownStyle" in violation.token for violation in violations)
    assert any("MarkdownFormattingDefinition" in violation.token for violation in violations)
    assert any("MarkdownShortcutProcessor" in violation.token for violation in violations)


def test_check_reports_backend_notes_runtime_legacy_references(
    tmp_path: Path,
) -> None:
    """Backend notes runtime files should fail on legacy note storage references."""
    _write(
        tmp_path / "backend/api/services/notes_service.py",
        """
        from api.services.notes_content_codec import canonical_note_content_from_plain_text

        def update(note, canonical):
            note.content = canonical.content
            note.content_format = "rtf"
        """,
    )

    violations = check(tmp_path)

    assert any("notes_content_codec" in violation.token for violation in violations)
    assert any(".content" in violation.token for violation in violations)
    assert any("content_format" in violation.token for violation in violations)


def test_check_reports_backend_notes_runtime_legacy_references_in_document_writer(
    tmp_path: Path,
) -> None:
    """Document-native note writer should also be scanned for legacy storage references."""
    _write(
        tmp_path / "backend/skills/notes/scripts/save_note_document.py",
        """
        from api.services.notes_content_codec import canonical_note_content_from_plain_text

        def save(document):
            content_format = "markdown"
            return canonical_note_content_from_plain_text(document), content_format
        """,
    )

    violations = check(tmp_path)

    assert any("notes_content_codec" in violation.token for violation in violations)
    assert any("content_format" in violation.token for violation in violations)


def test_check_reports_ios_notes_runtime_cleanup_leftovers(
    tmp_path: Path,
) -> None:
    """Phase 5 cleanup files should fail if dead formatting wrappers or bridge-only helpers remain."""
    _write(
        tmp_path / "ios/sideBar/sideBar/ViewModels/NoteFormatting.swift",
        """
        import Foundation
        enum NoteFormattingCapability: Hashable {
            case bold
        }
        extension NoteFormatting {
            var runtimeCapability: NoteFormattingCapability? { .bold }
        }
        """,
    )
    _write(
        tmp_path / "ios/sideBar/sideBar/ViewModels/NativeNoteEditorViewModel+Styling.swift",
        """
        import SwiftUI
        extension NativeNoteEditorViewModel {
            func platformSystemFont() {}
            func platformFontApplyingTraits() {}
            func swiftUIFontHasTrait() -> Bool { false }
        }
        """,
    )
    _write(
        tmp_path / "ios/sideBar/sideBar/Utilities/NotesRichTextCodec.swift",
        """
        import Foundation
        enum NotesRichTextCodec {
            static func export(_ content: AttributedString) {
                _ = try? NSAttributedString(content, including: \\.attributedNoteTextSurface)
            }
        }
        """,
    )
    _write(
        tmp_path / "ios/sideBar/sideBar/Utilities/NoteTextBridging.swift",
        """
        import SwiftUI
        extension AttributeScopes {
            var attributedNoteTextSurface: String { "legacy" }
        }
        """,
    )

    violations = check(tmp_path)

    assert any("NoteFormattingCapability" in violation.token for violation in violations)
    assert any("runtimeCapability" in violation.token for violation in violations)
    assert any("platformSystemFont" in violation.token for violation in violations)
    assert any("platformFontApplyingTraits" in violation.token for violation in violations)
    assert any("swiftUIFontHasTrait" in violation.token for violation in violations)
    assert any("attributedNoteTextSurface" in violation.token for violation in violations)


def test_check_passes_without_backend_legacy_note_storage_references(
    tmp_path: Path,
) -> None:
    """Clean backend notes runtime files should not trigger legacy storage violations."""
    _write(
        tmp_path / "backend/api/services/notes_service.py",
        """
        from api.services.notes_write_contract import build_canonical_note_write

        def update(note, document):
            canonical = build_canonical_note_write(document)
            note.document = canonical.document
            note.document_version = canonical.document_version
            note.plain_text = canonical.plain_text
            note.title = canonical.title
        """,
    )
    _write(
        tmp_path / "backend/api/services/notes_workspace_service.py",
        """
        def build_note_payload(note):
            return {
                "document": note.document,
                "plain_text": note.plain_text,
                "title": note.title,
            }
        """,
    )
    _write(
        tmp_path / "backend/skills/notes/scripts/save_note_document.py",
        """
        from api.services.notes_document_types import note_document_from_plain_text

        def save(document):
            plain_document = note_document_from_plain_text("plain")
            return document, plain_document
        """,
    )
    _write(
        tmp_path / "backend/skills/notes/scripts/read_note.py",
        """
        def read(note):
            return {
                "document": note.document,
                "plain_text": note.plain_text,
                "title": note.title,
            }
        """,
    )

    violations = [
        violation
        for violation in check(tmp_path)
        if str(violation.file_path).startswith(str(tmp_path / "backend"))
    ]

    assert violations == []


def test_check_passes_without_forbidden_references(tmp_path: Path) -> None:
    """No violations should be reported for clean runtime and shell files."""
    _write(
        tmp_path / "ios/sideBar/sideBar/ViewModels/NotesEditorViewModel.swift",
        """
        import Foundation
        public final class NotesEditorViewModel {
            func sharedNativeEditor() -> NativeNoteEditorViewModel {
                NativeNoteEditorViewModel()
            }
            func currentPersistenceSnapshot() {}
            func syncFromNativeEditor() {}
        }
        """,
    )
    _write(
        tmp_path / "ios/sideBar/sideBar/ViewModels/NativeNoteEditorViewModel+Persistence.swift",
        """
        import Foundation
        extension NativeNoteEditorViewModel {
            struct PersistenceSnapshot {
                let canonicalContent: String
                let plainText: String
            }
        }
        """,
    )
    _write(
        tmp_path / "ios/sideBar/sideBar/Views/Notes/AttributedNoteEditorContainer.swift",
        """
        import SwiftUI
        struct AttributedNoteEditorContainer: View {
            let editorViewModel = NotesEditorViewModel()
            @StateObject private var nativeViewModel: NativeNoteEditorViewModel

            init() {
                _nativeViewModel = StateObject(
                    wrappedValue: editorViewModel.sharedNativeEditor()
                )
            }

            var body: some View {
                Text("Notes")
                    .onAppear {
                        attachNativeEditor(nativeViewModel)
                        syncFromNativeEditor(nativeViewModel)
                    }
            }

            func attachNativeEditor(_ nativeViewModel: NativeNoteEditorViewModel) {}
            func syncFromNativeEditor(_ nativeViewModel: NativeNoteEditorViewModel) {}
        }
        """,
    )
    _write(
        tmp_path / "ios/sideBar/sideBar/Views/Notes/SwiftUINoteTextEditorSurface.swift",
        """
        import SwiftUI
        struct SwiftUINoteTextEditorSurface: View {
            @ObservedObject var viewModel: NativeNoteEditorViewModel

            var body: some View {
                TextEditor(text: $viewModel.attributedContent, selection: $viewModel.selection)
                    .attributedTextFormattingDefinition(NoteTextFormattingDefinition(baseFontSize: viewModel.baseFontSize))
                    .onChange(of: viewModel.attributedContent) { previous, _ in
                        viewModel.handleContentChange(previous: previous)
                    }
            }
        }
        """,
    )
    _write(
        tmp_path / "ios/sideBar/sideBar/ViewModels/NativeNoteEditorViewModel.swift",
        """
        import Foundation
        final class NativeNoteEditorViewModel {
            let attributedContent = ""
            let selection = ""
            let baseFontSize = 17.0
            func handleContentChange(previous: String) {}
        }
        """,
    )

    assert check(tmp_path) == []
