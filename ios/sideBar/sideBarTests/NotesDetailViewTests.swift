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

        let view = context.makeView()
        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        XCTAssertFalse(view.isShowingReadSurface)
        XCTAssertTrue(view.isShowingEditorSurface)
        XCTAssertTrue(view.isFormattingToolbarVisible)
    }

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
            context.editorViewModel.presentationMode == .read &&
                context.editorViewModel.saveErrorMessage == "Failed to save note"
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

    func testShortcutActionEventIgnoresEventsFromOtherSectionsOrPanes() async throws {
        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()

        context.makeView().handleShortcutActionEvent(
            ShortcutActionEvent(action: .closeItem, section: .chat, pane: .primary),
            workspacePane: .primary
        )
        context.makeView().handleShortcutActionEvent(
            ShortcutActionEvent(action: .closeItem, section: .notes, pane: .secondary),
            workspacePane: .primary
        )
        await Task.yield()

        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        XCTAssertEqual(context.editorViewModel.currentNoteId, "n1")
        XCTAssertNotNil(context.notesViewModel.activeNote)
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
        #if os(macOS)
        XCTAssertFalse(didInvokeEscape)
        await waitUntil(timeout: .milliseconds(150)) { didInvokeEscape }
        #endif
        XCTAssertTrue(didInvokeEscape)
    }

    func testAttributedNoteEditorContainerLeavesPendingTargetAvailableForMountedEditor() async throws {
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
        assertInsertionPointUTF16Offset(
            nativeViewModel.selection,
            in: nativeViewModel.attributedContent,
            equals: 5
        )
        XCTAssertEqual(
            context.editorViewModel.consumePendingEditSelectionTarget(),
            .characterOffset(5)
        )

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
        let pendingTarget = try XCTUnwrap(context.editorViewModel.consumePendingEditSelectionTarget())
        nativeViewModel.applySelectionTarget(pendingTarget)

        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        assertInsertionPointUTF16Offset(
            nativeViewModel.selection,
            in: nativeViewModel.attributedContent,
            equals: 5
        )

        context.store.applyEditorUpdate(makeTestNote(id: "n1", plainText: refreshedText))
        await waitUntil {
            String(nativeViewModel.attributedContent.characters) == refreshedText
        }

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
