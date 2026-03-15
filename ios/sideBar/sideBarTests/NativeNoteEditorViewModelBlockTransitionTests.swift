import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorBlockTransitionTests: XCTestCase {
    func testActiveTextStyleUsesSelectionStartBlockForMultiLineSelection() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let selectionStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let selectionEnd = viewModel.index(forCharacterOffset: 18, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)

        XCTAssertEqual(viewModel.activeTextStyle(), .heading)
    }

    func testApplyTextStyleConvertsEverySelectedTextStyleFamilyBlock() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "Body", marks: [.bold])]),
                .init(type: .subheading, content: [.init(text: "Tail", marks: [.italic])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let selectionStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let selectionEnd = viewModel.index(forCharacterOffset: 15, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)

        viewModel.applyTextStyle(.heading)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .heading, .heading])
        XCTAssertEqual(snapshot.document.blocks[1].content.first?.marks, [])
        XCTAssertEqual(snapshot.document.blocks[2].content.first?.marks, [.italic])
    }

    func testHandleReturnKeyExitsHeadingIntoParagraphBlock() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertTrue(viewModel.handleReturnKey())
        noteAppendTypedText("Body", to: viewModel)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .heading, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Body", marks: [])])
    }

    func testHandleReturnKeyExitsSubheadingIntoParagraphBlock() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subhead", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertTrue(viewModel.handleReturnKey())
        noteAppendTypedText("Body", to: viewModel)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .subheading, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Body", marks: [])])
    }

    func testHandleReturnKeyAfterBodyDoesNotMutateEarlierHeadingOrSubheadingBlocks() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertTrue(viewModel.handleReturnKey())
        noteAppendTypedText("Next", to: viewModel)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .heading, .subheading, .paragraph, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Heading", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Subheading", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[3].content, [.init(text: "Body", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[4].content, [.init(text: "Next", marks: [])])
    }

    func testHandleReturnKeyDoubleReturnExitsCodeBlockIntoParagraphBlock() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertTrue(viewModel.handleReturnKey())
        XCTAssertTrue(viewModel.handleReturnKey())
        noteAppendTypedText("Body", to: viewModel)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .codeBlock, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "let x = 1\n", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Body", marks: [])])
    }

    func testHandleReturnKeyOnEmptyTrailingParagraphAddsAnotherBlankParagraph() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])]),
                .paragraph([.init(text: "", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertTrue(viewModel.handleReturnKey())

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph, .paragraph, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Body", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[3].content, [.init(text: "", marks: [])])
        XCTAssertEqual(snapshot.plainText, "Title\nBody\n\n")
    }
}
