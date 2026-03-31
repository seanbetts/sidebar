import SwiftUI
import XCTest
@testable import sideBar

@MainActor
extension NotesDetailViewTests {
    #if os(iOS)
    @available(iOS 26.0, *)
    func testHandleCloseShortcutCapturesViewportBeforeResponderDismissalShiftsOffset() async throws {
        let context = await makeNotesDetailViewTestContext()
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        let textView = ViewportShiftingAccessoryTextView()
        textView.contentOffset = CGPoint(x: 0, y: 240)
        textView.offsetAfterResign = CGPoint(x: 0, y: 420)
        context.editorViewModel.attachNativeEditorTextView(textView)
        context.editorViewModel.enterEditMode()

        context.makeView().handleCloseShortcut()

        await waitUntil(timeout: .milliseconds(250)) {
            context.editorViewModel.presentationMode == .read
        }

        XCTAssertEqual(
            context.editorViewModel.debugLastExitReadViewportRestoration?.offset,
            CGPoint(x: 0, y: 240)
        )
    }
    #endif

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
        assertNotesDetailInsertionPointUTF16Offset(
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
        assertNotesDetailInsertionPoint(
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

        #if os(iOS)
        await waitUntil(timeout: .milliseconds(150)) {
            context.editorViewModel.presentationMode == .edit
        }
        #endif

        loadedNoteId = AttributedNoteEditorContainer.loadNoteIfNeeded(
            editorViewModel: context.editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: loadedNoteId
        )
        let pendingTarget = try XCTUnwrap(context.editorViewModel.consumePendingEditSelectionTarget())
        nativeViewModel.applySelectionTarget(pendingTarget)

        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        assertNotesDetailInsertionPointUTF16Offset(
            nativeViewModel.selection,
            in: nativeViewModel.attributedContent,
            equals: 5
        )

        context.store.applyEditorUpdate(makeTestNote(id: "n1", plainText: refreshedText))
        await waitUntil {
            String(nativeViewModel.attributedContent.characters) == refreshedText
        }

        XCTAssertEqual(String(nativeViewModel.attributedContent.characters), refreshedText)
        assertNotesDetailInsertionPointUTF16Offset(
            nativeViewModel.selection,
            in: nativeViewModel.attributedContent,
            equals: 5
        )
    }
}

#if os(iOS)
@available(iOS 26.0, *)
@MainActor
private final class ViewportShiftingAccessoryTextView: UIKitNoteTextEditorSurface.AccessoryTextView {
    var offsetAfterResign: CGPoint?

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if let offsetAfterResign {
            contentOffset = offsetAfterResign
        }
        return didResign
    }
}
#endif
