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

    func testTitleProjectionFallsBackWhenBlockZeroIsNotTitle() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "   ", marks: [])]),
                .paragraph([.init(text: "# Hello world", marks: [])])
            ]
        )

        XCTAssertEqual(NotesSemanticDocumentProjection.title(from: document), "New Note")
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

    func testPlainTextProjectionSupportsStructuredBlockTypes() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Release Notes", marks: [])]),
                .init(type: .heading, content: [.init(text: "Sprint", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Today", marks: [])]),
                .init(type: .unorderedList, content: [.init(text: "Ship schema", marks: [])]),
                .init(type: .orderedList, content: [.init(text: "Run tests", marks: [])]),
                .init(
                    type: .checklist,
                    content: [.init(text: "Completed item", marks: [.strikethrough])],
                    checked: true
                ),
                .init(type: .blockquote, content: [.init(text: "Quoted line", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "line 1\nline 2", marks: [])])
            ]
        )

        XCTAssertEqual(
            NotesSemanticDocumentProjection.plainText(from: document),
            """
            Release Notes
            Sprint
            Today
            - Ship schema
            1. Run tests
            - [x] Completed item
            > Quoted line
            line 1
            line 2
            """
        )
    }

    func testPlainTextProjectionUsesLinkTextOrUrlFallback() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Read ", marks: []),
                    .init(text: "Docs", marks: [], link: .init(url: "https://example.com/docs"))
                ]),
                .paragraph([
                    .init(text: "", marks: [], link: .init(url: "https://example.com/fallback"))
                ])
            ]
        )

        XCTAssertEqual(
            NotesSemanticDocumentProjection.plainText(from: document),
            "Read Docs\nhttps://example.com/fallback"
        )
    }

    func testTitleProjectionUsesBlockZeroTitleSemantics() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "  Semantic Title  ", marks: [])]),
                .paragraph([.init(text: "# body heading style", marks: [])])
            ]
        )

        XCTAssertEqual(NotesSemanticDocumentProjection.title(from: document), "Semantic Title")
    }

    func testSemanticDocumentCodecDecodesLegacyTaskListAliasAsChecklist() throws {
        let json = """
        {
          "version": 1,
          "blocks": [
            {
              "type": "title",
              "content": [{"text": "Title", "marks": []}]
            },
            {
              "type": "task_list",
              "content": [{"text": "Legacy item", "marks": []}]
            }
          ]
        }
        """

        let document = try XCTUnwrap(NotesSemanticDocumentCodec.decode(json))

        XCTAssertEqual(document.blocks[1].type, .checklist)
        XCTAssertNil(document.blocks[1].checked)
    }
}
