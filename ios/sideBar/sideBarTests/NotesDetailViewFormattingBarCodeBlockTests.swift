import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesFormattingCodeBlockTests: NotesDetailViewHostingTestCase {
    func testFormattingBarConfigurationCodeBlockTapConvertsParagraphToCodeBlock() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "let x = 1", marks: [])])
                ]
            ),
            plainText: "Title\nlet x = 1",
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
        let insertion = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isEnabled)
        XCTAssertFalse(configuration.isCodeBlockActive)
        XCTAssertTrue(configuration.isCodeBlockEnabled)

        configuration.onCodeBlockTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .codeBlock])
        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isCodeBlockActive)
    }

    func testFormattingBarConfigurationCodeBlockTapTogglesCodeBlockBackToParagraph() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: .codeBlock, content: [.init(text: "let x = 1", marks: [])])
                ]
            ),
            plainText: "Title\nlet x = 1",
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
        let insertion = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isCodeBlockActive)
        XCTAssertTrue(configuration.isCodeBlockEnabled)

        configuration.onCodeBlockTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertFalse(context.makeView().noteFormattingBarConfiguration.isCodeBlockActive)
    }
}
