import XCTest
@testable import sideBar

#if os(macOS)
@MainActor
final class NotesDetailViewMountedMacOSTests: NotesDetailViewHostingTestCase {
    private let mountedNotesLifetimeIterations = 10

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
                        .init(type: .heading, content: [.init(text: "Heading", marks: [])])
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
