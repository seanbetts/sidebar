import SwiftUI
import XCTest
@testable import sideBar

#if os(macOS)
@MainActor
final class NotesDetailViewMacOSStabilityTests: NotesDetailViewHostingTestCase {
    @available(iOS 26.0, macOS 26.0, *)
    func testReadEditToggleKeepsNoteIdentityWhileUsingAppKitEditHost() async throws {
        let harness = await MountedNotesDetailHarness(note: makeTestNote(id: "toggle-note", plainText: "A👍🏽B"))
        harness.mount()
        await harness.settle()

        let noteId = try XCTUnwrap(harness.context.notesViewModel.activeNote?.id)
        XCTAssertTrue(harness.context.makeView().isShowingReadSurface)

        harness.context.makeView().activateReadSurfaceEditing(at: .characterOffset(5))
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        XCTAssertEqual(harness.context.editorViewModel.currentNoteId, noteId)
        XCTAssertEqual(harness.context.notesViewModel.activeNote?.id, noteId)
        XCTAssertTrue(try attributedNoteEditorContainerMountsAppKitSurfaceDirectly())
        XCTAssertFalse(try attributedNoteEditorContainerMountsSwiftUISurfaceDirectly())

        harness.context.makeView().handleCloseShortcut()
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .read
        }

        XCTAssertEqual(harness.context.editorViewModel.currentNoteId, noteId)
        XCTAssertEqual(harness.context.notesViewModel.activeNote?.id, noteId)
        XCTAssertTrue(harness.context.makeView().isShowingReadSurface)
        harness.dispose()
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

    func testNativeEditorSelectionTargetDoesNotCrashAcrossRepeatedReset() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        for _ in 0..<notesLifetimeSmokeIterations {
            let context = await makeNotesDetailViewTestContext(
                note: makeTestNote(plainText: "A👍🏽B")
            )
            let nativeViewModel = NativeNoteEditorViewModel()
            context.editorViewModel.attachNativeEditor(nativeViewModel)
            context.makeView().activateReadSurfaceEditing(at: .characterOffset(5))

            _ = AttributedNoteEditorContainer.loadNoteIfNeeded(
                editorViewModel: context.editorViewModel,
                nativeViewModel: nativeViewModel,
                loadedNoteId: nil
            )
            XCTAssertEqual(context.editorViewModel.presentationMode, .edit)

            NotesDetailViewTestRetainer.reset()
            drainNotesHostingRunLoop()
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    func testMountedDetailEditActivationKeepsPendingCaretAtRequestedEndOfNoteOffset() async throws {
        let harness = await MountedNotesDetailHarness(
            note: makeTestNote(id: "caret-note", plainText: "A👍🏽B")
        )
        harness.mount()
        await harness.settle()

        let nativeViewModel = harness.activateReadSurfaceEditing(at: .characterOffset(5))

        XCTAssertEqual(
            nativeViewModel.utf16SelectedRange(in: nativeViewModel.attributedContent),
            NSRange(location: 5, length: 0)
        )
        harness.dispose()
    }

    func testMountedDetailEditActivationMakesEditorFirstResponderOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness(
            note: makeTestNote(plainText: "Short note")
        )
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .characterOffset(0))

        await waitUntil(timeout: .seconds(2)) {
            guard let editorTextView = findDescendantTextView(in: harness.mountedView) else { return false }
            return editorTextView.isEditable
                && harness.mountedView.window?.firstResponder === editorTextView
        }

        let editorTextView = try XCTUnwrap(findDescendantTextView(in: harness.mountedView))
        XCTAssertTrue(editorTextView.isEditable)
        XCTAssertTrue(harness.mountedView.window?.firstResponder === editorTextView)
        XCTAssertEqual(editorTextView.selectedRange(), NSRange(location: 0, length: 0))
        harness.dispose()
    }

    func testMountedDetailEditActivationKeepsCaretAtRequestedMidDocumentOffsetOnMacOS() async throws {
        let longLine = Array(repeating: "Long wrapped segment", count: 40).joined(separator: " ")
        let targetOffset = 57
        let harness = await MountedNotesDetailHarness(
            note: makeTestNote(plainText: longLine)
        )
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .characterOffset(targetOffset))

        await waitUntil(timeout: .seconds(2)) {
            guard let editorTextView = findDescendantTextView(in: harness.mountedView) else { return false }
            return editorTextView.isEditable
                && harness.mountedView.window?.firstResponder === editorTextView
                && editorTextView.selectedRange() == NSRange(location: targetOffset, length: 0)
        }

        let editorTextView = try XCTUnwrap(findDescendantTextView(in: harness.mountedView))
        XCTAssertEqual(editorTextView.selectedRange(), NSRange(location: targetOffset, length: 0))
        harness.dispose()
    }

    func testMountedDetailToggleKeepsLongParagraphWrappedOnMacOS() async throws {
        let longParagraph = Array(repeating: "Long wrapped segment", count: 80).joined(separator: " ")
        let lastCharacterIndex = max(longParagraph.utf16.count - 1, 0)
        let context = await makeNotesDetailViewTestContext(
            note: makeTestNote(id: "wrapping-note", plainText: longParagraph)
        )
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(
            context.makeView().environmentObject(environment),
            frame: CGRect(x: 0, y: 0, width: 420, height: 700)
        )
        let mountedView = controller.view
        mountedView.layoutSubtreeIfNeeded()
        mountedView.window?.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        let initialReadTextView = try XCTUnwrap(findDescendantTextView(in: mountedView))
        XCTAssertFalse(initialReadTextView.isEditable)
        try assertMountedTextViewWrapsLongParagraph(
            initialReadTextView,
            lastCharacterIndex: lastCharacterIndex
        )

        context.makeView().activateReadSurfaceEditing(at: .characterOffset(0))

        let editorTextView = try await waitForMountedTextView(in: mountedView) { textView in
            textView.isEditable
        }
        try assertMountedTextViewWrapsLongParagraph(
            editorTextView,
            lastCharacterIndex: lastCharacterIndex
        )

        context.makeView().handleCloseShortcut()

        let restoredReadTextView = try await waitForMountedTextView(in: mountedView) { textView in
            textView.isEditable == false
        }
        try assertMountedTextViewWrapsLongParagraph(
            restoredReadTextView,
            lastCharacterIndex: lastCharacterIndex
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    func testMountedEscapeAfterTypedBlockquoteLeavesEditModeOnMacOS() async throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "", marks: [])])
            ]
        )
        let note = NotePayload(
            id: "typed-blockquote-note",
            name: "Title",
            document: document,
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            path: "/typed-blockquote-note.md",
            modified: nil,
            created: nil
        )
        let harness = await MountedNotesDetailHarness(note: note)
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        let nativeViewModel = harness.activateReadSurfaceEditing(at: .characterOffset(6))

        await waitUntil(timeout: .seconds(2)) {
            guard let editorTextView = findDescendantTextView(in: harness.mountedView) else { return false }
            return harness.context.editorViewModel.presentationMode == .edit
                && editorTextView.isEditable
                && harness.mountedWindow.firstResponder === editorTextView
        }

        noteAppendTypedText(">", to: nativeViewModel)
        XCTAssertTrue(nativeViewModel.handleTextReplacement(" "))
        drainNotesHostingRunLoop()

        let editorTextView = try XCTUnwrap(findDescendantTextView(in: harness.mountedView))
        XCTAssertTrue(editorTextView.string.contains("> "))

        editorTextView.cancelOperation(nil)

        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .read
                && harness.mountedWindow.firstResponder !== editorTextView
        }

        XCTAssertEqual(harness.context.editorViewModel.presentationMode, .read)
        XCTAssertFalse(harness.mountedWindow.firstResponder === editorTextView)
        XCTAssertTrue(harness.context.makeView().isShowingReadSurface)
        XCTAssertFalse(harness.context.makeView().isShowingEditorSurface)
    }

    @available(iOS 26.0, macOS 26.0, *)
    func testMountedContainerEscapeClearsFirstResponderOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness(note: makeTestNote(plainText: "Title\n\nBody"))
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        let nativeViewModel = harness.activateReadSurfaceEditing(at: .characterOffset(0))

        await waitUntil(timeout: .seconds(2)) {
            guard let editorTextView = findDescendantTextView(in: harness.mountedView) else { return false }
            return harness.context.editorViewModel.presentationMode == .edit
                && harness.mountedWindow.firstResponder === editorTextView
        }

        let editorTextView = try XCTUnwrap(findDescendantTextView(in: harness.mountedView))
        let container = AttributedNoteEditorContainer(
            editorViewModel: harness.context.editorViewModel,
            maxContentWidth: NoteTextLayout.maxContentWidth,
            onEscape: harness.context.makeView().handleEscapeKey
        )

        XCTAssertEqual(
            container.handleEscapeKey(document: nativeViewModel.currentPersistenceSnapshot().document),
            .handled
        )

        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .read
                && harness.mountedWindow.firstResponder !== editorTextView
        }

        XCTAssertEqual(harness.context.editorViewModel.presentationMode, .read)
        XCTAssertFalse(harness.mountedWindow.firstResponder === editorTextView)
    }

}

@MainActor
private func waitForMountedTextView(
    in rootView: NSView,
    matching predicate: @escaping (NSTextView) -> Bool
) async throws -> NSTextView {
    var resolvedTextView: NSTextView?
    await waitUntil(timeout: .seconds(2)) {
        guard let textView = findDescendantTextView(in: rootView), predicate(textView) else {
            return false
        }
        resolvedTextView = textView
        return true
    }
    return try XCTUnwrap(resolvedTextView)
}

@MainActor
private func assertMountedTextViewWrapsLongParagraph(
    _ textView: NSTextView,
    lastCharacterIndex: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    textView.layoutSubtreeIfNeeded()
    textView.enclosingScrollView?.layoutSubtreeIfNeeded()
    textView.window?.contentView?.layoutSubtreeIfNeeded()
    drainNotesHostingRunLoop()

    let firstCharacterRect = try glyphRect(in: textView, characterIndex: 0)
    let lastCharacterRect = try glyphRect(in: textView, characterIndex: lastCharacterIndex)

    XCTAssertGreaterThan(
        lastCharacterRect.minY,
        firstCharacterRect.minY + 1,
        "Expected the mounted note surface to wrap long paragraphs instead of laying them out on one overflowing line.",
        file: file,
        line: line
    )
}
#endif
