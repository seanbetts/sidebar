import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorListTypingTriggerTests: XCTestCase {
    func testTypingSpaceAfterDashAtParagraphStartConvertsToUnorderedList() async throws {
        let viewModel = try makeViewModelForEmptyBodyParagraph()
        noteAppendTypedText("-", to: viewModel)

        XCTAssertTrue(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .unorderedList])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .unorderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "", marks: [])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n- ")
        XCTAssertEqual(
            selectionInsertionOffset(in: viewModel),
            viewModel.attributedContent.characters.count
        )
    }

    func testTypingSpaceAfterAsteriskAtParagraphStartConvertsToUnorderedList() async throws {
        let viewModel = try makeViewModelForEmptyBodyParagraph()
        noteAppendTypedText("*", to: viewModel)

        XCTAssertTrue(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .unorderedList])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .unorderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "", marks: [])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n- ")
    }

    func testTypingSpaceAfterOneDotAtParagraphStartConvertsToOrderedList() async throws {
        let viewModel = try makeViewModelForEmptyBodyParagraph()
        noteAppendTypedText("1.", to: viewModel)

        XCTAssertTrue(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .orderedList])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .orderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "", marks: [])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n1. ")
        XCTAssertEqual(
            selectionInsertionOffset(in: viewModel),
            viewModel.attributedContent.characters.count
        )
    }

    func testTypingSpaceAfterGreaterThanAtParagraphStartConvertsToBlockquote() async throws {
        let viewModel = try makeViewModelForEmptyBodyParagraph()
        noteAppendTypedText(">", to: viewModel)

        XCTAssertTrue(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .blockquote])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .blockquote,
                children: [
                    .paragraph([.init(text: "", marks: [])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n> ")
        XCTAssertEqual(
            selectionInsertionOffset(in: viewModel),
            viewModel.attributedContent.characters.count
        )
    }

    func testTypingSpaceDoesNotTriggerListConversionAwayFromParagraphStart() async throws {
        let viewModel = try makeViewModelForBodyParagraph("Alpha-")

        XCTAssertFalse(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Alpha-", marks: [])])
    }

    func testTypingSpaceDoesNotTriggerListConversionForRangeSelection() async throws {
        let viewModel = try makeViewModelForBodyParagraph("-")
        let lower = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let upper = viewModel.index(forCharacterOffset: 7, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: lower..<upper)

        XCTAssertFalse(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "-", marks: [])])
    }

    func testTypingSpaceDoesNotTriggerListConversionOutsideParagraphBlocks() async throws {
        for blockType in [
            NotesSemanticDocument.BlockType.title,
            .heading,
            .subheading,
            .codeBlock,
            .blockquote
        ] {
            let viewModel = try makeViewModel(blockType: blockType, text: blockType == .title ? "Title-" : "-")

            XCTAssertFalse(
                viewModel.handleTextReplacement(" "),
                "Expected no trigger for block type \(blockType)"
            )
        }

        let listViewModel = NativeNoteEditorViewModel()
        let listDocument = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "-", marks: [])])
                    ]
                )
            ]
        )
        listViewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(listDocument)),
            plainText: NotesSemanticDocumentProjection.plainText(from: listDocument)
        )
        let insertion = listViewModel.attributedContent.endIndex
        listViewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertFalse(listViewModel.handleTextReplacement(" "))
    }

    func testTypingSpaceDoesNotTriggerListConversionForMultiCharacterReplacement() async throws {
        let viewModel = try makeViewModelForBodyParagraph("-")

        XCTAssertFalse(viewModel.handleTextReplacement("  "))
        XCTAssertFalse(viewModel.handleTextReplacement("- "))
    }

    private func makeViewModelForEmptyBodyParagraph() throws -> NativeNoteEditorViewModel {
        try makeViewModelForBodyParagraph("")
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

    private func makeViewModel(
        blockType: NotesSemanticDocument.BlockType,
        text: String
    ) throws -> NativeNoteEditorViewModel {
        let document: NotesSemanticDocument
        if blockType == .title {
            document = NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: text, marks: [])])
                ]
            )
        } else {
            document = NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: blockType, content: [.init(text: text, marks: [])])
                ]
            )
        }

        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        return viewModel
    }

    private func selectionInsertionOffset(in viewModel: NativeNoteEditorViewModel) -> Int {
        switch viewModel.selectionSnapshot(in: viewModel.attributedContent) {
        case .insertionPoint(let offset):
            return offset
        case .ranges(let ranges):
            XCTFail("Expected insertion point, got ranges \(ranges)")
            return -1
        }
    }
}
