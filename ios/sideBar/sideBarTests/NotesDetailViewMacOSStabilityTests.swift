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

    func testMountedViewCloseShortcutReturnsToReadBeforeDelayedSaveCompletesOnMacOS() async throws {
        let api = NotesDetailViewDelayingNotesAPI(updateDelayNanoseconds: 500_000_000)
        let harness = await MountedNotesDetailHarness(api: api)
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            guard let editorTextView = findDescendantTextView(in: harness.mountedView) else { return false }
            return editorTextView.isEditable
        }

        let editorTextView = try XCTUnwrap(findDescendantTextView(in: harness.mountedView))
        editorTextView.setSelectedRange(NSRange(location: 0, length: editorTextView.string.utf16.count))
        editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "Delayed save body"))
        editorTextView.didChangeText()
        drainNotesHostingRunLoop()
        XCTAssertEqual(
            NotesSemanticDocumentProjection.plainText(
                from: harness.context.editorViewModel.currentSemanticDocumentSnapshot()
            ),
            "Delayed save body"
        )

        harness.environment.activeSection = .notes
        harness.environment.focusedSection = .notes
        harness.environment.focusedWorkspacePane = .primary
        harness.emitCloseShortcut()
        await waitUntil(timeout: .milliseconds(150)) {
            harness.context.editorViewModel.presentationMode == .read
                && harness.context.editorViewModel.isSaving
                && api.updateCallCount == 1
        }

        XCTAssertEqual(harness.context.editorViewModel.presentationMode, .read)
        XCTAssertTrue(harness.context.editorViewModel.isSaving)
        XCTAssertEqual(harness.context.editorViewModel.content, "Delayed save body")
        await waitUntil(timeout: .seconds(2)) {
            api.updateCallCount == 1
        }
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.isSaving == false
        }
        await waitUntil(timeout: .seconds(2)) {
            harness.context.notesViewModel.activeNote?.plainText == "Delayed save body"
        }
        XCTAssertEqual(harness.context.notesViewModel.activeNote?.plainText, "Delayed save body")
        harness.dispose()
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

    func testMountedDetailEditActivationFromMiddlePreservesViewportAnchorOnMacOS() async throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment)
        let readTextView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let readScrollView = try XCTUnwrap(readTextView.enclosingScrollView)
        let targetOffset = NSString(string: plainText).range(of: "Line 70 body text").location
        let initialTargetRect = try glyphRect(in: readTextView, characterIndex: targetOffset)
        let targetReadOffset = max(
            initialTargetRect.midY - (readScrollView.contentView.bounds.height * 0.55),
            0
        )
        readScrollView.contentView.scroll(to: NSPoint(x: 0, y: targetReadOffset))
        readScrollView.reflectScrolledClipView(readScrollView.contentView)
        drainNotesHostingRunLoop()

        let expectedViewportAnchorY = try mountedViewportAnchorY(
            in: readTextView,
            scrollView: readScrollView,
            characterIndex: targetOffset
        )

        context.makeView().activateReadSurfaceEditing(
            at: .characterOffset(targetOffset),
            viewportAnchorY: expectedViewportAnchorY
        )
        await waitUntil(timeout: .seconds(2)) {
            guard let editorTextView = findDescendantTextView(in: controller.view) else { return false }
            return editorTextView.isEditable
        }

        let editorTextView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let editorScrollView = try XCTUnwrap(editorTextView.enclosingScrollView)
        let actualViewportAnchorY = try mountedViewportAnchorY(
            in: editorTextView,
            scrollView: editorScrollView,
            characterIndex: targetOffset
        )

        XCTAssertEqual(editorTextView.selectedRange(), NSRange(location: targetOffset, length: 0))
        XCTAssertEqual(actualViewportAnchorY, expectedViewportAnchorY, accuracy: 24)
    }

    func testMountedDetailCloseShortcutPreservesViewportOffsetAndFocusOnMacOS() async throws {
        let plainText = (0..<150)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment)

        context.editorViewModel.enterEditMode()
        await waitUntil(timeout: .seconds(2)) {
            guard let editorTextView = findDescendantTextView(in: controller.view) else { return false }
            return editorTextView.isEditable
        }

        let editorTextView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let editorScrollView = try XCTUnwrap(editorTextView.enclosingScrollView)
        let targetOffset = NSString(string: plainText).range(of: "Line 95 body text").location
        let targetRect = try glyphRect(in: editorTextView, characterIndex: targetOffset)
        let targetEditorOffset = max(
            targetRect.midY - (editorScrollView.contentView.bounds.height * 0.55),
            0
        )
        editorScrollView.contentView.scroll(to: NSPoint(x: 0, y: targetEditorOffset))
        editorScrollView.reflectScrolledClipView(editorScrollView.contentView)
        drainNotesHostingRunLoop()

        let expectedReadOffset = editorScrollView.contentView.bounds.origin.y
        environment.activeSection = .notes
        environment.focusedSection = .notes
        environment.focusedWorkspacePane = .primary
        environment.emitShortcutAction(.closeItem)

        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.presentationMode == .read
        }
        await waitUntil(timeout: .seconds(2)) {
            guard let textView = findDescendantTextView(in: controller.view) else { return false }
            return textView.isEditable == false
        }
        await waitUntil(timeout: .seconds(2)) {
            guard let textView = findDescendantTextView(in: controller.view) else { return false }
            return controller.view.window?.firstResponder === textView
        }
        drainNotesHostingRunLoop()

        let readTextView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let readScrollView = try XCTUnwrap(readTextView.enclosingScrollView)
        XCTAssertFalse(readTextView.isEditable)
        XCTAssertEqual(readScrollView.contentView.bounds.origin.y, expectedReadOffset, accuracy: 2)
        XCTAssertTrue(controller.view.window?.firstResponder === readTextView)
    }

}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func mountedViewportAnchorY(
    in textView: NSTextView,
    scrollView: NSScrollView,
    characterIndex: Int
) throws -> CGFloat {
    let rect = try glyphRect(in: textView, characterIndex: characterIndex)
    return rect.midY - scrollView.contentView.bounds.minY
}
#endif
