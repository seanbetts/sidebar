import XCTest
@testable import sideBar

#if os(macOS)
@MainActor
final class NotesDetailViewMacOSStabilityTests: NotesDetailViewHostingTestCase {
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
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func testUnsupportedNotesPlaceholderDoesNotCrashAcrossRepeatedReset() async throws {
        for iteration in 0..<notesLifetimeSmokeIterations {
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

            NotesDetailViewTestRetainer.reset()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
#endif
