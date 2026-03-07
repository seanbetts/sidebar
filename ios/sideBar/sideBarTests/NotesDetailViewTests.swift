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

    func testActivateReadSurfaceEditingSwitchesToEditorSurface() async {
        let context = await makeNotesDetailViewTestContext()

        context.makeView().activateReadSurfaceEditing()

        let view = context.makeView()
        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        XCTAssertFalse(view.isShowingReadSurface)
        XCTAssertTrue(view.isShowingEditorSurface)
        XCTAssertTrue(view.isFormattingToolbarVisible)
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

        environment.emitShortcutAction(.closeItem)
        await waitUntil {
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
}
