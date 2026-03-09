import XCTest
@testable import sideBar

#if os(macOS)
@MainActor
final class NotesDetailViewMountedMacOSTests: NotesDetailViewHostingTestCase {
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

    func testMountedReadSurfaceAndNativeEditorScenariosDoNotCrashAcrossRepeatedReset() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        for iteration in 0..<10 {
            do {
                let context = await makeNotesDetailViewTestContext()
                let environment = makeNotesDetailTestEnvironment()
                _ = mount(context.makeView(), environment: environment)
                await Task.yield()
                environment.activeSection = .notes
                environment.focusedSection = .notes
                environment.focusedWorkspacePane = .primary
                environment.emitShortcutAction(.closeItem)
                await waitUntil(timeout: .seconds(2)) {
                    context.editorViewModel.currentNoteId == nil
                }
            }

            NotesDetailViewTestRetainer.reset()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            do {
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
            }

            NotesDetailViewTestRetainer.reset()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            do {
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
                let context = await makeNotesDetailViewTestContext(note: unsupportedNote)
                let view = context.makeView()
                XCTAssertTrue(view.isShowingUnsupportedContentPlaceholder)
                XCTAssertFalse(view.isShowingReadSurface)
                XCTAssertFalse(view.isShowingEditorSurface)
            }

            NotesDetailViewTestRetainer.reset()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
#endif
