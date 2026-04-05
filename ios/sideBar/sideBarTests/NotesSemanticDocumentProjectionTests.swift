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
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Ship schema", marks: [])])
                    ]
                ),
                .init(
                    type: .orderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Run tests", marks: [])])
                    ]
                ),
                .init(
                    type: .checklist,
                    children: [
                        .init(
                            type: .listItem,
                            content: [.init(text: "Completed item", marks: [.strikethrough])],
                            checked: true
                        )
                    ]
                ),
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Quoted line", marks: [])])
                    ]
                ),
                .init(type: .divider),
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

    func testPlainTextProjectionSupportsNestedVersionTwoContainers() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Release Notes", marks: [])]),
                .init(
                    type: .orderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Run tests", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Ship build", marks: [])])
                    ]
                ),
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Done", marks: [])], checked: true),
                        .init(type: .listItem, content: [.init(text: "Next", marks: [])], checked: false)
                    ]
                ),
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Quoted line", marks: [])])
                    ]
                ),
                .init(type: .codeBlock, content: [.init(text: "let x = 1", marks: [])])
            ]
        )

        XCTAssertEqual(
            NotesSemanticDocumentProjection.plainText(from: document),
            """
            Release Notes
            1. Run tests
            2. Ship build
            - [x] Done
            - [ ] Next
            > Quoted line
            let x = 1
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

    func testPlainTextProjectionProjectsDividerAsBlankSeparator() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Weekly plan", marks: [])]),
                .paragraph([.init(text: "Top priorities", marks: [])]),
                .init(type: .divider),
                .paragraph([.init(text: "Backlog review", marks: [])])
            ]
        )

        XCTAssertEqual(
            NotesSemanticDocumentProjection.plainText(from: document),
            """
            Weekly plan
            Top priorities

            Backlog review
            """
        )
    }

    func testSemanticDocumentNormalizesDividerAsContentlessLeafBlock() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .divider,
                    content: [.init(text: "---", marks: [])],
                    children: [
                        .paragraph([.init(text: "Ignored", marks: [])])
                    ]
                )
            ]
        )

        XCTAssertEqual(
            document.blocks,
            [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .divider)
            ]
        )
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

        XCTAssertEqual(document.version, NotesSemanticDocument.currentVersion)
        XCTAssertEqual(document.blocks[1].type, .checklist)
        XCTAssertEqual(
            document.blocks[1].children,
            [
                .init(
                    type: .listItem,
                    content: [.init(text: "Legacy item", marks: [])],
                    checked: false
                )
            ]
        )
        XCTAssertNil(document.blocks[1].checked)
    }

    func testSemanticDocumentCodecAdaptsVersionOneFlatOrderedListIntoVersionTwoContainer() throws {
        let json = """
        {
          "version": 1,
          "blocks": [
            {
              "type": "title",
              "content": [{"text": "Title", "marks": []}]
            },
            {
              "type": "ordered_list",
              "content": [{"text": "First", "marks": []}]
            }
          ]
        }
        """

        let document = try XCTUnwrap(NotesSemanticDocumentCodec.decode(json))

        XCTAssertEqual(document.version, NotesSemanticDocument.currentVersion)
        XCTAssertEqual(
            document.blocks,
            [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .orderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [])])
                    ]
                )
            ]
        )
    }
}
