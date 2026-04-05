import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesDetailViewFormattingBarDividerTests: NotesDetailViewHostingTestCase {
    func testFormattingBarConfigurationDividerTapInsertsDividerAfterCurrentParagraph() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "Body", marks: [])])
                ]
            ),
            plainText: "Title\nBody",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        _ = await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.currentNoteId == "n1"
        }
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let insertion = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isDividerEnabled)
        XCTAssertFalse(configuration.isDividerActive)

        configuration.onDividerTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .paragraph, .divider, .paragraph])
        XCTAssertEqual(document.blocks[2], .init(type: .divider))
        XCTAssertEqual(document.blocks[3], .paragraph([.init(text: "", marks: [])]))
        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isDividerActive)
    }
}
