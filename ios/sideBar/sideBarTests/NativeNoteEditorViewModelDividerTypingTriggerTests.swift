import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorDividerTypingTriggerTests: XCTestCase {
    func testTypingThirdDashAtEmptyParagraphStartConvertsToDivider() async throws {
        let viewModel = try makeViewModelForBodyParagraph("")
        noteAppendTypedText("--", to: viewModel)

        XCTAssertTrue(viewModel.handleTextReplacement("-"))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .divider, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1], .init(type: .divider))
        XCTAssertEqual(snapshot.document.blocks[2], .paragraph([.init(text: "", marks: [])]))
        XCTAssertEqual(snapshot.plainText, "Title\n\n")
    }

    func testTypingThirdDashDoesNotConvertWhenParagraphAlreadyHasContent() async throws {
        let viewModel = try makeViewModelForBodyParagraph("Alpha--")

        XCTAssertFalse(viewModel.handleTextReplacement("-"))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Alpha--", marks: [])])
    }

    private func makeViewModelForBodyParagraph(_ bodyText: String) throws -> NativeNoteEditorViewModel {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: bodyText, marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        return viewModel
    }
}
