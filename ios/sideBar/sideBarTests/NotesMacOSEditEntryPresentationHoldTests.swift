#if os(macOS)
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesMacOSEditEntryPresentationHoldTests: NotesDetailViewHostingTestCase {
    func testEnterEditModeStartsReadSurfaceHoldOnMacOSWithoutViewportAnchor() async {
        let context = await makeNotesDetailViewTestContext(
            note: makeTestNote(
                id: "macos-edit-entry-hold",
                plainText: "A long line that should stay visually stable while edit mode mounts."
            )
        )
        context.editorViewModel.enterEditMode(
            at: NotesEditorViewModel.PendingEditSelectionTarget.start
        )

        XCTAssertTrue(
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry,
            "Expected macOS edit entry to keep the read surface mounted until "
                + "the editor reports its first stable presentation."
        )

        context.editorViewModel.completeEditEntryPresentationHold()

        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false
        }
    }

    func testActivateReadSurfaceEditingKeepsReadSurfaceVisibleDuringMacOSEditEntryHold() async {
        let context = await makeNotesDetailViewTestContext(
            note: makeTestNote(
                id: "macos-read-hold",
                plainText: Array(repeating: "Long wrapped segment", count: 80).joined(separator: " ")
            )
        )

        context.makeView().activateReadSurfaceEditing(
            at: NotesEditorViewModel.PendingEditSelectionTarget.start
        )

        let view = context.makeView()
        XCTAssertEqual(context.editorViewModel.presentationMode, .edit)
        XCTAssertTrue(context.editorViewModel.isHoldingReadSurfaceDuringEditEntry)
        XCTAssertTrue(
            view.isReadSurfaceVisibleForCurrentPresentation,
            "Expected the read surface to remain visible during macOS edit "
                + "entry so the transient AppKit layout bootstrap never "
                + "flashes onscreen."
        )
    }
}
#endif
