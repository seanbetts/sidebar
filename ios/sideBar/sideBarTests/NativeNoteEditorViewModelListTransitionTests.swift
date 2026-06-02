import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorListTransitionTests: XCTestCase {
    func testToggleUnorderedListConvertsSelectedParagraphBlocksIntoSingleContainer() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "First", marks: [.bold])]),
                .paragraph([.init(text: "Second", marks: [.italic])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let selectionStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let selectionEnd = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)

        viewModel.toggleList(.unorderedList)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .unorderedList])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .unorderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "First", marks: [.bold])]),
                    .init(type: .listItem, content: [.init(text: "Second", marks: [.italic])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n- First\n- Second")
    }

    func testToggleOrderedListConvertsSelectedParagraphBlocksIntoSingleContainer() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "Alpha", marks: [])]),
                .paragraph([.init(text: "Beta", marks: [.underline])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let selectionStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let selectionEnd = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)

        viewModel.toggleList(.orderedList)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .orderedList])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .orderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "Alpha", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Beta", marks: [.underline])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n1. Alpha\n2. Beta")
    }

    func testToggleBlockquoteConvertsSelectedParagraphBlocksIntoSingleContainer() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "First", marks: [.bold])]),
                .paragraph([.init(text: "Second", marks: [.italic])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let selectionStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let selectionEnd = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)

        viewModel.toggleList(.blockquote)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .blockquote])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .blockquote,
                children: [
                    .paragraph([.init(text: "First", marks: [.bold])]),
                    .paragraph([.init(text: "Second", marks: [.italic])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n> First\n> Second")
    }

    func testToggleUnorderedListPreservesSelectionAcrossInsertedPrefixes() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "First", marks: [])]),
                .paragraph([.init(text: "Second", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let selectionStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let selectionEnd = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)

        viewModel.toggleList(.unorderedList)

        XCTAssertEqual(String(viewModel.attributedContent.characters), "Title\n• First\n• Second")
        switch viewModel.selectionSnapshot(in: viewModel.attributedContent) {
        case .ranges(let ranges):
            XCTAssertEqual(ranges, [8..<22])
        case .insertionPoint(let offset):
            XCTFail("Expected selection range, got insertion point at \(offset)")
        }
    }

    func testToggleOrderedListConvertsActiveUnorderedListInPlace() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [.bold])]),
                        .init(type: .listItem, content: [.init(text: "Second", marks: [.italic])])
                    ]
                )
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let selectionStart = viewModel.index(forCharacterOffset: 8, in: viewModel.attributedContent)
        let selectionEnd = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)

        viewModel.toggleList(.orderedList)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .orderedList])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .orderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "First", marks: [.bold])]),
                    .init(type: .listItem, content: [.init(text: "Second", marks: [.italic])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n1. First\n2. Second")
    }

    func testHandleReturnKeyAtEndOfUnorderedListContinuesWithNewListItem() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [])])
                    ]
                )
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
        noteAppendTypedText("Second", to: viewModel)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .unorderedList])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .unorderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "First", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Second", marks: [])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n- First\n- Second")
    }

    func testHandleReturnKeyAtEndOfBlockquoteContinuesWithNewQuotedParagraph() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "First", marks: [])])
                    ]
                )
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
        noteAppendTypedText("Second", to: viewModel)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .blockquote])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .blockquote,
                children: [
                    .paragraph([.init(text: "First", marks: [])]),
                    .paragraph([.init(text: "Second", marks: [])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n> First\n> Second")
    }

    func testHandleReturnKeyOnEmptyTrailingUnorderedListItemExitsIntoParagraph() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "", marks: [])])
                    ]
                )
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
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .unorderedList, .paragraph])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .unorderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "First", marks: [])])
                ]
            )
        )
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Body", marks: [])])
        XCTAssertEqual(snapshot.plainText, "Title\n- First\nBody")
    }

    func testHandleReturnKeyOnEmptyTrailingBlockquoteParagraphExitsIntoParagraph() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "First", marks: [])]),
                        .paragraph([.init(text: "", marks: [])])
                    ]
                )
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
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .blockquote, .paragraph])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .blockquote,
                children: [
                    .paragraph([.init(text: "First", marks: [])])
                ]
            )
        )
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Body", marks: [])])
        XCTAssertEqual(snapshot.plainText, "Title\n> First\nBody")
    }

    func testMultilinePasteInsideChecklistItemCreatesChecklistItems() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [])], checked: true)
                    ]
                )
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertTrue(viewModel.handleTextReplacement("\nSecond\nThird"))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .checklist])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "First", marks: [])], checked: true),
                    .init(type: .listItem, content: [.init(text: "Second", marks: [])], checked: false),
                    .init(type: .listItem, content: [.init(text: "Third", marks: [])], checked: false)
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n- [x] First\n- [ ] Second\n- [ ] Third")
    }

    func testMultilinePasteInsideBlockquoteCreatesQuotedParagraphs() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "First", marks: [])])
                    ]
                )
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertTrue(viewModel.handleTextReplacement("\nSecond\nThird"))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .blockquote])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .blockquote,
                children: [
                    .paragraph([.init(text: "First", marks: [])]),
                    .paragraph([.init(text: "Second", marks: [])]),
                    .paragraph([.init(text: "Third", marks: [])])
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n> First\n> Second\n> Third")
    }

    func testToggleUnorderedListConvertsActiveListBackIntoParagraphBlocks() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [.bold])]),
                        .init(type: .listItem, content: [.init(text: "Second", marks: [.italic])])
                    ]
                )
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let selectionStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let selectionEnd = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)

        viewModel.toggleList(.unorderedList)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "First", marks: [.bold])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Second", marks: [.italic])])
        XCTAssertEqual(snapshot.plainText, "Title\nFirst\nSecond")
    }

    func testToggleBlockquoteConvertsActiveBlockquoteBackIntoParagraphBlocks() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "First", marks: [.bold])]),
                        .paragraph([.init(text: "Second", marks: [.italic])])
                    ]
                )
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let selectionStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let selectionEnd = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)

        viewModel.toggleList(.blockquote)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "First", marks: [.bold])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Second", marks: [.italic])])
        XCTAssertEqual(snapshot.plainText, "Title\nFirst\nSecond")
    }
}
