import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesDetailViewTests: NotesDetailViewHostingTestCase {
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

    func testCompactPhoneRoutePendingSelectionWhenRouteAndSelectedNoteDiffer() {
        XCTAssertTrue(
            NotesDetailView.isCompactPhoneRoutePendingSelection(
                isCompact: true,
                routeNoteId: "note-2",
                selectedNoteId: "note-1"
            )
        )
    }

    func testCompactPhoneRouteNotPendingWhenRouteMatchesSelectedNote() {
        XCTAssertFalse(
            NotesDetailView.isCompactPhoneRoutePendingSelection(
                isCompact: true,
                routeNoteId: "note-1",
                selectedNoteId: "note-1"
            )
        )
    }

    func testActivateReadSurfaceEditingKeepsFormattingToolbarVisibleDuringTransition() async {
        let context = await makeNotesDetailViewTestContext()

        context.makeView().activateReadSurfaceEditing(at: .start)

        #if os(iOS)
        await waitUntil(timeout: .milliseconds(150)) {
            context.editorViewModel.presentationMode == .edit
        }
        #endif

        let view = context.makeView()
        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        XCTAssertFalse(view.isShowingReadSurface)
        XCTAssertTrue(view.isShowingEditorSurface)
        XCTAssertTrue(view.isFormattingToolbarVisible)
    }

    #if os(iOS)
    @available(iOS 26.0, *)
    func testActivateReadSurfaceEditingDefersPresentationModeUntilNextMainQueueTurnOnIOS() async {
        let context = await makeNotesDetailViewTestContext()

        context.makeView().activateReadSurfaceEditing(at: .start)

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)

        await waitUntil(timeout: .milliseconds(150)) {
            context.editorViewModel.presentationMode == .edit
        }
        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
    }
    #endif

    func testUnsupportedNotesShowPlaceholderInsteadOfReadOrEditorSurface() async {
        let unsupportedNote = NotePayload(
            id: "n1",
            name: "Unsupported",
            document: NotesSemanticDocument(
                blocks: [
                    .paragraph([.init(text: "Intro", marks: [])]),
                    .init(type: .table, content: [.init(text: "Cell", marks: [])])
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
            "This note contains unsupported content blocks: table."
        )
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

    func testRequestCloseNoteCollapsesWorkspaceStateAfterClose() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppStorageKeys.workspaceExpanded)
        #if os(iOS)
        defaults.set(true, forKey: AppStorageKeys.workspaceExpandedByRotation)
        #endif
        defer {
            defaults.removeObject(forKey: AppStorageKeys.workspaceExpanded)
            #if os(iOS)
            defaults.removeObject(forKey: AppStorageKeys.workspaceExpandedByRotation)
            #endif
        }

        let context = await makeNotesDetailViewTestContext()
        context.makeView().requestCloseNote()
        await waitUntil {
            context.notesViewModel.activeNote == nil
        }

        XCTAssertFalse(defaults.bool(forKey: AppStorageKeys.workspaceExpanded))
        #if os(iOS)
        XCTAssertFalse(defaults.bool(forKey: AppStorageKeys.workspaceExpandedByRotation))
        #endif
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
        await waitUntil {
            api.updateCallCount == 1 &&
                context.editorViewModel.presentationMode == .read &&
                context.notesViewModel.activeNote?.plainText == "Updated from edit mode"
        }

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
            context.editorViewModel.presentationMode == .read &&
                context.editorViewModel.saveErrorMessage == "Failed to save note"
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

    func testEscapeFromEditorReturnsToReadBeforeDelayedSaveCompletes() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let api = NotesDetailViewDelayingNotesAPI(updateDelayNanoseconds: 500_000_000)
        let context = await makeNotesDetailViewTestContext(api: api)
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
        nativeViewModel.attributedContent = AttributedString("Delayed save body")
        nativeViewModel.handleContentChange(previous: previous)

        XCTAssertEqual(
            container.handleEscapeKey(
                document: nativeViewModel.currentPersistenceSnapshot().document
            ),
            .handled
        )
        await waitUntil(timeout: .milliseconds(150)) {
            context.editorViewModel.presentationMode == .read
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        await waitUntil(timeout: .milliseconds(150)) {
            context.notesViewModel.activeNote?.plainText == "Delayed save body"
                && api.updateCallCount == 1
        }
        XCTAssertEqual(context.notesViewModel.activeNote?.plainText, "Delayed save body")
        XCTAssertEqual(api.updateCallCount, 1)
    }

    func testEscapeFromEditorAfterBlockquoteTypingTriggerTransitionsToReadWithSemanticBlockquoteSnapshot() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "", marks: [])])
            ]
        )
        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: document,
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let view = context.makeView()
        let container = AttributedNoteEditorContainer(
            editorViewModel: context.editorViewModel,
            maxContentWidth: 640,
            onEscape: view.handleEscapeKey
        )

        let insertion = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        noteAppendTypedText(">", to: nativeViewModel)
        XCTAssertTrue(nativeViewModel.handleTextReplacement(" "))

        XCTAssertEqual(
            container.handleEscapeKey(
                document: nativeViewModel.currentPersistenceSnapshot().document
            ),
            .handled
        )
        await waitUntil {
            context.editorViewModel.presentationMode == .read &&
                context.notesViewModel.activeNote?.plainText == "Title\n> "
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        let activeNote = try XCTUnwrap(context.notesViewModel.activeNote)
        XCTAssertEqual(activeNote.document.blocks.map(\.type), [.title, .blockquote])

        let mixedDocument = NotesSemanticDocument(
            version: activeNote.document.version,
            blocks: activeNote.document.blocks + [
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Existing", marks: [])])
                    ]
                )
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: mixedDocument,
            baseFontSize: 16
        )
        XCTAssertEqual(attributed.string, "Title\n\nExisting")
        XCTAssertFalse(attributed.string.contains("> "))
    }

    func testHandleCloseShortcutClosesNoteFromReadModeEvenWhenNativeEditorRemainsAttached() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let context = await makeNotesDetailViewTestContext()
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        context.editorViewModel.exitEditModeToRead()

        await waitUntil(timeout: .milliseconds(150)) {
            context.editorViewModel.presentationMode == .read
        }
        XCTAssertNotNil(context.editorViewModel.attachedNativeEditorViewModel)

        context.makeView().handleCloseShortcut()
        await waitUntil(timeout: .milliseconds(150)) {
            context.editorViewModel.currentNoteId == nil &&
                context.notesViewModel.activeNote == nil
        }

        XCTAssertNil(context.editorViewModel.currentNoteId)
        XCTAssertNil(context.notesViewModel.activeNote)
    }

    func testHandleEscapeKeyClosesNoteWhenPresentationAlreadyRead() async throws {
        let context = await makeNotesDetailViewTestContext()
        let view = context.makeView()
        let document = try XCTUnwrap(context.notesViewModel.activeNote?.document)

        context.editorViewModel.presentationMode = .read

        view.handleEscapeKey(document)
        await waitUntil(timeout: .milliseconds(150)) {
            context.editorViewModel.currentNoteId == nil &&
                context.notesViewModel.activeNote == nil
        }

        XCTAssertNil(context.editorViewModel.currentNoteId)
        XCTAssertNil(context.notesViewModel.activeNote)
    }

    func testHandleCloseShortcutFromReadModeClosesByNextMainActorTurn() async throws {
        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.presentationMode = .read

        context.makeView().handleCloseShortcut()
        await Task.yield()

        XCTAssertNil(context.editorViewModel.currentNoteId)
        XCTAssertNil(context.notesViewModel.activeNote)
    }

    func testReadInitialViewportRestorationAppliedDefersPendingRestorationCleanup() async {
        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.setPendingReadSurfaceViewportRestoration(
            offset: CGPoint(x: 0, y: 184),
            target: nil,
            viewportAnchorY: nil
        )

        await waitUntil(timeout: .milliseconds(150)) {
            context.editorViewModel.pendingReadSurfaceViewportOffset == CGPoint(x: 0, y: 184)
        }

        context.makeView().handleReadInitialViewportRestorationApplied()

        XCTAssertEqual(context.editorViewModel.pendingReadSurfaceViewportOffset, CGPoint(x: 0, y: 184))
        await waitUntil(timeout: .milliseconds(150)) {
            context.editorViewModel.pendingReadSurfaceViewportOffset == nil
        }
        XCTAssertEqual(context.editorViewModel.heldReadSurfaceViewportOffset, CGPoint(x: 0, y: 184))
        XCTAssertNil(context.editorViewModel.pendingReadSurfaceViewportAnchorTarget)
        XCTAssertNil(context.editorViewModel.pendingReadSurfaceViewportAnchorY)
    }
}

@available(iOS 26.0, macOS 26.0, *)
func assertNotesDetailInsertionPoint(
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
func assertNotesDetailInsertionPointUTF16Offset(
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
