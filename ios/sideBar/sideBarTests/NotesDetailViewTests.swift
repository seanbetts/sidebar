import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesDetailViewTests: XCTestCase {
    func testNotesDetailViewTypeLoads() {
        XCTAssertNotNil(NotesDetailView.self)
    }

    func testDisplayTitleUsesActiveNoteName() async {
        let context = await makeNotesDetailViewTestContext(
            note: makeTestNote(name: "Semantic title", plainText: "Semantic title")
        )

        XCTAssertEqual(context.makeView().displayTitle, "Semantic title")
    }

    func testOpenNoteShowsReadSurfaceFirst() async {
        let context = await makeNotesDetailViewTestContext()
        let view = context.makeView()

        XCTAssertTrue(view.isShowingReadSurface)
        XCTAssertFalse(view.isShowingEditorSurface)
        XCTAssertFalse(view.isFormattingToolbarVisible)
    }

    func testActivateReadSurfaceEditingKeepsFormattingToolbarVisibleDuringTransition() async {
        let context = await makeNotesDetailViewTestContext()

        context.makeView().activateReadSurfaceEditing(at: .start)

        let view = context.makeView()
        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        XCTAssertFalse(view.isShowingReadSurface)
        XCTAssertTrue(view.isShowingEditorSurface)
        XCTAssertTrue(view.isFormattingToolbarVisible)
    }

    func testActivateReadSurfaceEditingPassesTargetIntoEnterEditMode() async {
        let context = await makeNotesDetailViewTestContext()

        context.makeView().activateReadSurfaceEditing(at: .characterOffset(7))

        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        XCTAssertEqual(
            context.editorViewModel.consumePendingEditSelectionTarget(),
            .characterOffset(7)
        )
    }

    func testUnsupportedNotesShowPlaceholderInsteadOfReadOrEditorSurface() async {
        let unsupportedNote = NotePayload(
            id: "n1",
            name: "Unsupported",
            document: NotesSemanticDocument(
                blocks: [
                    .paragraph([.init(text: "Intro", marks: [])]),
                    .init(type: .heading, content: [.init(text: "Heading", marks: [])])
                ]
            ),
            plainText: "Intro",
            path: "/unsupported.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: unsupportedNote)
        let view = context.makeView()

        XCTAssertTrue(view.isShowingUnsupportedContentPlaceholder)
        XCTAssertFalse(view.isShowingReadSurface)
        XCTAssertFalse(view.isShowingEditorSurface)
        XCTAssertFalse(view.isFormattingToolbarVisible)
        XCTAssertEqual(view.unsupportedContentPlaceholderTitle, "Unsupported note content")
        XCTAssertEqual(
            view.unsupportedContentPlaceholderMessage,
            "This note contains unsupported content blocks: heading."
        )
    }

    func testUnsupportedNotesCannotEnterEditModeFromReadSurfaceActivation() async {
        let unsupportedNote = NotePayload(
            id: "n1",
            name: "Unsupported",
            document: NotesSemanticDocument(
                blocks: [
                    .paragraph([.init(text: "Intro", marks: [])]),
                    .init(type: .heading, content: [.init(text: "Heading", marks: [])])
                ]
            ),
            plainText: "Intro",
            path: "/unsupported.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: unsupportedNote)

        context.makeView().activateReadSurfaceEditing(at: .start)

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertFalse(context.editorViewModel.isEditingNote)
        XCTAssertTrue(context.makeView().isShowingUnsupportedContentPlaceholder)
    }

    func testHandleCloseShortcutReturnsEditModeToReadWithoutClosingNote() async {
        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()

        context.makeView().handleCloseShortcut()
        await Task.yield()
        await Task.yield()

        let view = context.makeView()
        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertEqual(context.editorViewModel.currentNoteId, "n1")
        XCTAssertNotNil(context.notesViewModel.activeNote)
        XCTAssertTrue(view.isShowingReadSurface)
    }

    func testHandleCloseShortcutClosesNoteWhenAlreadyInReadMode() async {
        let context = await makeNotesDetailViewTestContext()

        context.makeView().handleCloseShortcut()
        await waitUntil {
            context.editorViewModel.currentNoteId == nil &&
            context.notesViewModel.activeNote == nil
        }

        XCTAssertNil(context.editorViewModel.currentNoteId)
        XCTAssertNil(context.notesViewModel.activeNote)
    }

    func testRequestCloseNoteClosesNoteFromEditMode() async {
        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()

        context.makeView().requestCloseNote()
        await waitUntil {
            context.editorViewModel.currentNoteId == nil &&
            context.notesViewModel.activeNote == nil
        }

        XCTAssertNil(context.editorViewModel.currentNoteId)
        XCTAssertNil(context.notesViewModel.activeNote)
    }

    func testRequestCloseNoteClosesNoteFromReadMode() async {
        let context = await makeNotesDetailViewTestContext()

        context.makeView().requestCloseNote()
        await waitUntil {
            context.editorViewModel.currentNoteId == nil &&
            context.notesViewModel.activeNote == nil
        }

        XCTAssertNil(context.editorViewModel.currentNoteId)
        XCTAssertNil(context.notesViewModel.activeNote)
    }

    func testHandleCloseShortcutSyncsUnsavedEditorContentBeforeReturningToReadMode() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let api = NotesDetailViewRecordingNotesAPI()
        let context = await makeNotesDetailViewTestContext(api: api)
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let previous = nativeViewModel.attributedContent
        nativeViewModel.attributedContent = AttributedString("Updated from edit mode")
        nativeViewModel.handleContentChange(previous: previous)

        context.makeView().handleCloseShortcut()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(api.updateCallCount, 1)
        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertEqual(context.editorViewModel.content, "Updated from edit mode")
        XCTAssertEqual(context.notesViewModel.activeNote?.plainText, "Updated from edit mode")
    }

    func testEscapeFromEditorPreservesUnsavedContentWhenSaveFails() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let context = await makeNotesDetailViewTestContext(api: NotesDetailViewFailingNotesAPI())
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let view = context.makeView()
        let container = AttributedNoteEditorContainer(
            editorViewModel: context.editorViewModel,
            maxContentWidth: 640,
            onEscape: view.handleEscapeKey
        )

        let previous = nativeViewModel.attributedContent
        nativeViewModel.attributedContent = AttributedString("Unsaved latest text")
        nativeViewModel.handleContentChange(previous: previous)

        XCTAssertEqual(
            container.handleEscapeKey(
                document: nativeViewModel.currentPersistenceSnapshot().document
            ),
            .handled
        )
        await waitUntil {
            context.editorViewModel.presentationMode == .read
        }

        let cachedDocument = try XCTUnwrap(
            NotesSemanticDocumentCodec.decode(context.editorViewModel.canonicalContent)
        )
        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertEqual(context.editorViewModel.content, "Unsaved latest text")
        XCTAssertEqual(
            NotesSemanticDocumentProjection.plainText(from: cachedDocument),
            "Unsaved latest text"
        )
        XCTAssertEqual(context.editorViewModel.saveErrorMessage, "Failed to save note")
    }

    func testMountedViewCloseShortcutEventReturnsEditModeToRead() async throws {
        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()
        let environment = makeNotesDetailTestEnvironment()
        _ = mount(context.makeView(), environment: environment)
        await Task.yield()
        environment.activeSection = .notes
        environment.focusedSection = .notes
        environment.focusedWorkspacePane = .primary

        environment.emitShortcutAction(.closeItem)
        await waitUntil {
            context.editorViewModel.presentationMode == .read
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertNotNil(context.notesViewModel.activeNote)
    }

    func testHandleCloseShortcutPreservesUnsavedContentWithoutExplicitDocumentWhenSaveFails() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let context = await makeNotesDetailViewTestContext(api: NotesDetailViewFailingNotesAPI())
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let previous = nativeViewModel.attributedContent
        nativeViewModel.attributedContent = AttributedString("Shortcut unsaved text")
        nativeViewModel.handleContentChange(previous: previous)

        context.makeView().handleCloseShortcut()
        await waitUntil {
            context.editorViewModel.presentationMode == .read
        }

        let cachedDocument = try XCTUnwrap(
            NotesSemanticDocumentCodec.decode(context.editorViewModel.canonicalContent)
        )
        XCTAssertEqual(context.editorViewModel.content, "Shortcut unsaved text")
        XCTAssertEqual(
            NotesSemanticDocumentProjection.plainText(from: cachedDocument),
            "Shortcut unsaved text"
        )
        XCTAssertEqual(context.editorViewModel.saveErrorMessage, "Failed to save note")
    }

    func testMountedViewCloseShortcutEventClosesReadModeNote() async throws {
        let context = await makeNotesDetailViewTestContext()
        let environment = makeNotesDetailTestEnvironment()
        _ = mount(context.makeView(), environment: environment)
        await Task.yield()
        environment.activeSection = .notes
        environment.focusedSection = .notes
        environment.focusedWorkspacePane = .primary
        await Task.yield()

        environment.emitShortcutAction(.closeItem)
        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.currentNoteId == nil
        }

        XCTAssertNil(context.editorViewModel.currentNoteId)
        XCTAssertNil(context.notesViewModel.activeNote)
    }

    func testAttributedNoteEditorContainerHandleEscapeInvokesCallbackWhenNoteOpen() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let context = await makeNotesDetailViewTestContext()
        var didInvokeEscape = false
        let container = AttributedNoteEditorContainer(
            editorViewModel: context.editorViewModel,
            maxContentWidth: 640,
            onEscape: { _ in didInvokeEscape = true }
        )

        let result = container.handleEscapeKey(
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Hello world")
        )

        XCTAssertEqual(result, .handled)
        XCTAssertTrue(didInvokeEscape)
    }

    func testAttributedNoteEditorContainerConsumesPendingTargetOnceAfterEditorLoad() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello world"))
        let nativeViewModel = NativeNoteEditorViewModel()
        context.editorViewModel.enterEditMode(at: .characterOffset(5))
        var loadedNoteId: String?

        loadedNoteId = AttributedNoteEditorContainer.loadNoteIfNeeded(
            editorViewModel: context.editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: loadedNoteId
        )

        XCTAssertEqual(loadedNoteId, "n1")
        assertInsertionPoint(
            nativeViewModel.selectionSnapshot(in: nativeViewModel.attributedContent),
            equals: 5
        )
        XCTAssertNil(context.editorViewModel.consumePendingEditSelectionTarget())

        nativeViewModel.setInsertionPoint(characterOffset: 1)
        loadedNoteId = AttributedNoteEditorContainer.loadNoteIfNeeded(
            editorViewModel: context.editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: loadedNoteId
        )

        XCTAssertEqual(loadedNoteId, "n1")
        assertInsertionPoint(
            nativeViewModel.selectionSnapshot(in: nativeViewModel.attributedContent),
            equals: 1
        )
    }

    func testAttributedNoteEditorContainerAppliesUTF16PendingCaretTargetForComposedCharacters() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "A👍🏽B"))
        let nativeViewModel = NativeNoteEditorViewModel()
        context.editorViewModel.enterEditMode(at: .characterOffset(5))

        _ = AttributedNoteEditorContainer.loadNoteIfNeeded(
            editorViewModel: context.editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: nil
        )

        assertInsertionPointUTF16Offset(
            nativeViewModel.selection,
            in: nativeViewModel.attributedContent,
            equals: 5
        )
    }

    func testEditModeFormattingToolbarKeepsSwiftUIEditorSurfaceForPhaseOne() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let context = await makeNotesDetailViewTestContext()
        context.makeView().activateReadSurfaceEditing(at: .start)

        let view = context.makeView()

        XCTAssertTrue(view.isFormattingToolbarVisible)
        XCTAssertEqual(AttributedNoteEditorContainer.preferredEditorSurfaceKind, .swiftUI)
    }

    func testFormattingCommandsUpdateCanonicalSemanticSnapshotWithoutWrapperOnlyState() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let range = noteCharacterRange(length: 5, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: range)

        context.editorViewModel.setFormatting(.bold, enabled: true)

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        let paragraph = try XCTUnwrap(document.blocks.first)
        let segment = try XCTUnwrap(paragraph.content.first)

        XCTAssertEqual(segment.text, "Hello")
        XCTAssertTrue(segment.marks.contains(.bold))
        XCTAssertTrue(noteRangeHasBoldTrait(nativeViewModel.attributedContent, range: range))
    }

    func testReadSurfaceEditingRestoresUTF16CaretForComposedCharactersAfterSameNoteReload() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let initialText = "A👍🏽B"
        let refreshedText = "A👍🏽BC"
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: initialText))
        let nativeViewModel = NativeNoteEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.makeView().activateReadSurfaceEditing(at: .characterOffset(5))
        var loadedNoteId: String?

        loadedNoteId = AttributedNoteEditorContainer.loadNoteIfNeeded(
            editorViewModel: context.editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: loadedNoteId
        )

        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        assertInsertionPointUTF16Offset(
            nativeViewModel.selection,
            in: nativeViewModel.attributedContent,
            equals: 5
        )
        XCTAssertNil(context.editorViewModel.consumePendingEditSelectionTarget())

        context.store.applyEditorUpdate(makeTestNote(id: "n1", plainText: refreshedText))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(String(nativeViewModel.attributedContent.characters), refreshedText)
        assertInsertionPointUTF16Offset(
            nativeViewModel.selection,
            in: nativeViewModel.attributedContent,
            equals: 5
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func assertInsertionPoint(
    _ snapshot: NativeNoteEditorViewModel.SelectionSnapshot,
    equals expectedOffset: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .insertionPoint(let offset) = snapshot else {
        return XCTFail("Expected insertion point selection", file: file, line: line)
    }
    XCTAssertEqual(offset, expectedOffset, file: file, line: line)
}

@available(iOS 26.0, macOS 26.0, *)
private func assertInsertionPointUTF16Offset(
    _ selection: AttributedTextSelection,
    in text: AttributedString,
    equals expectedOffset: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let string = String(text.characters)
    switch selection.indices(in: text) {
    case .insertionPoint(let index):
        let characterOffset = text.characters.distance(from: text.startIndex, to: index)
        let stringIndex = string.index(string.startIndex, offsetBy: characterOffset)
        XCTAssertEqual(stringIndex.utf16Offset(in: string), expectedOffset, file: file, line: line)
    case .ranges:
        XCTFail("Expected insertion point selection", file: file, line: line)
    }
}
