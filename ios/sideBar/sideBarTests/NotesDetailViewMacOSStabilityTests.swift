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

}
#endif
