import XCTest
@testable import sideBar

final class NotesSemanticDocumentProjectionTests: XCTestCase {
    func testPlainTextProjectionJoinsParagraphBlocksWithNewlines() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Hello", marks: [.bold]),
                    .init(text: " world", marks: [])
                ]),
                .paragraph([
                    .init(text: "", marks: []),
                    .init(text: "Again", marks: [.underline])
                ])
            ]
        )

        XCTAssertEqual(NotesSemanticDocumentProjection.plainText(from: document), "Hello world\nAgain")
    }

    func testTitleProjectionUsesFirstNonEmptyProjectedLine() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "   ", marks: [])]),
                .paragraph([.init(text: "# Hello world", marks: [])])
            ]
        )

        XCTAssertEqual(NotesSemanticDocumentProjection.title(from: document), "Hello world")
    }

    func testTitleProjectionFallsBackToNewNote() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "", marks: [])]),
                .paragraph([.init(text: "   ", marks: [.italic])])
            ]
        )

        XCTAssertEqual(NotesSemanticDocumentProjection.title(from: document), "New Note")
    }
}
