import XCTest
@testable import sideBar

#if os(macOS)
@MainActor
final class NotesDetailViewMountedMacOSTests: NotesDetailViewHostingTestCase {
    private let mountedNotesLifetimeIterations = 10

    func testMacOSEditorContainerNoLongerPrefersRetiredSwiftUISurface() {
        XCTAssertNotEqual(AttributedNoteEditorContainer.preferredEditorSurfaceKind, .swiftUI)
    }

    @available(iOS 26.0, macOS 26.0, *)
    func testMountedEditModeRoutesThroughAppKitHostInsteadOfSwiftUISurface() async throws {
        let harness = await MountedNotesDetailHarness()
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        let view = harness.context.makeView()
        XCTAssertTrue(view.isShowingEditorSurface)
        XCTAssertTrue(try attributedNoteEditorContainerMountsAppKitSurfaceDirectly())
        XCTAssertFalse(try attributedNoteEditorContainerMountsSwiftUISurfaceDirectly())
        harness.dispose()
    }

    func testMountedViewCloseShortcutEventClosesReadModeNote() async throws {
        let harness = await MountedNotesDetailHarness()
        harness.mount()
        await harness.settle()
        harness.environment.activeSection = .notes
        harness.environment.focusedSection = .notes
        harness.environment.focusedWorkspacePane = .primary
        harness.emitCloseShortcut()
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.currentNoteId == nil
        }

        XCTAssertNil(harness.context.editorViewModel.currentNoteId)
        XCTAssertNil(harness.context.notesViewModel.activeNote)
        harness.dispose()
    }

    func testMountedCloseShortcutDoesNotCrashAcrossRepeatedReset() async throws {
        for _ in 0..<mountedNotesLifetimeIterations {
            let harness = await MountedNotesDetailHarness()
            harness.mount()
            await harness.settle()
            harness.environment.activeSection = .notes
            harness.environment.focusedSection = .notes
            harness.environment.focusedWorkspacePane = .primary
            harness.emitCloseShortcut()
            await waitUntil(timeout: .seconds(2)) {
                harness.context.editorViewModel.currentNoteId == nil
            }

            harness.dispose()
        }
    }

    func testMountedReadSurfaceActivationDoesNotCrashAcrossRepeatedReset() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        for _ in 0..<mountedNotesLifetimeIterations {
            let harness = await MountedNotesDetailHarness(
                note: makeTestNote(plainText: "A👍🏽B")
            )
            harness.mount()
            await harness.settle()
            _ = harness.activateReadSurfaceEditing(at: .characterOffset(5))
            XCTAssertEqual(harness.context.editorViewModel.presentationMode, .edit)

            harness.dispose()
        }
    }

    func testMountedUnsupportedNotePlaceholderDoesNotCrashAcrossRepeatedReset() async throws {
        for iteration in 0..<mountedNotesLifetimeIterations {
            let unsupportedNote = NotePayload(
                id: "unsupported-\(iteration)",
                name: "Unsupported",
                document: NotesSemanticDocument(
                    blocks: [
                        .paragraph([.init(text: "Intro", marks: [])]),
                        .init(type: .table, content: [.init(text: "Cell", marks: [])])
                    ]
                ),
                plainText: "Intro",
                path: "/unsupported-\(iteration).md",
                modified: nil,
                created: nil
            )
            let harness = await MountedNotesDetailHarness(note: unsupportedNote)
            harness.mount()
            let view = harness.context.makeView()
            XCTAssertTrue(view.isShowingUnsupportedContentPlaceholder)
            XCTAssertFalse(view.isShowingReadSurface)
            XCTAssertFalse(view.isShowingEditorSurface)

            harness.dispose()
        }
    }
}
#endif
