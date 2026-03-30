import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorChecklistLogicTests: XCTestCase {
    func testTypingSpaceAfterChecklistTriggerAtParagraphStartConvertsToChecklist() async throws {
        let viewModel = try makeViewModelForBodyParagraph("[]")

        XCTAssertTrue(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .checklist])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "", marks: [])], checked: false)
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n- [ ] ")
        XCTAssertEqual(
            selectionInsertionOffset(in: viewModel),
            viewModel.attributedContent.characters.count
        )
    }

    func testTypingSpaceDoesNotTriggerChecklistConversionForRangeSelection() async throws {
        let viewModel = try makeViewModelForBodyParagraph("[]")
        let lower = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let upper = viewModel.index(forCharacterOffset: 11, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: lower..<upper)

        XCTAssertFalse(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "[]", marks: [])])
    }

    func testTypingSpaceDoesNotTriggerChecklistConversionForNonSpaceReplacement() async throws {
        let viewModel = try makeViewModelForBodyParagraph("[]")

        XCTAssertFalse(viewModel.handleTextReplacement("  "))
        XCTAssertFalse(viewModel.handleTextReplacement("[] "))
    }

    func testTypingSpaceAfterLegacyChecklistTriggerDoesNotConvertToChecklist() async throws {
        let viewModel = try makeViewModelForBodyParagraph("- [ ]")

        XCTAssertFalse(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "- [ ]", marks: [])])
    }

    func testToggleChecklistConvertsSelectedParagraphsIntoSingleChecklistContainer() async throws {
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

        viewModel.toggleList(.checklist)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .checklist])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "First", marks: [.bold])], checked: false),
                    .init(type: .listItem, content: [.init(text: "Second", marks: [.italic])], checked: false)
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n- [ ] First\n- [ ] Second")
    }

    func testCheckedChecklistItemProjectsDerivedCompletionStylingWithoutSemanticStrikethroughMark() throws {
        let viewModel = try makeViewModel(
            from: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(
                        type: .checklist,
                        children: [
                            .init(type: .listItem, content: [.init(text: "Done", marks: [])], checked: true)
                        ]
                    )
                ]
            )
        )

        let content = viewModel.attributedContent
        let itemStart = content.index(content.startIndex, offsetByCharacters: 12)

        XCTAssertTrue(noteRangeIsStruckThrough(content, range: itemStart..<content.endIndex))
        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks[1].children?.first?.content.first?.marks, [])
        XCTAssertEqual(snapshot.document.blocks[1].children?.first?.checked, true)
    }

    func testUncheckedChecklistItemDoesNotReceiveDerivedCompletionStyling() throws {
        let viewModel = try makeViewModel(
            from: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(
                        type: .checklist,
                        children: [
                            .init(type: .listItem, content: [.init(text: "Todo", marks: [])], checked: false)
                        ]
                    )
                ]
            )
        )

        let content = viewModel.attributedContent
        let itemStart = content.index(content.startIndex, offsetByCharacters: 12)

        XCTAssertFalse(noteRangeIsStruckThrough(content, range: itemStart..<content.endIndex))
    }

    func testHandleReturnKeyAtEndOfChecklistContinuesWithUncheckedChecklistItem() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [])], checked: false)
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
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .checklist])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "First", marks: [])], checked: false),
                    .init(type: .listItem, content: [.init(text: "Second", marks: [])], checked: false)
                ]
            )
        )
        XCTAssertEqual(snapshot.plainText, "Title\n- [ ] First\n- [ ] Second")
    }

    func testHandleReturnKeyOnEmptyTrailingChecklistItemExitsIntoParagraph() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [])], checked: false),
                        .init(type: .listItem, content: [.init(text: "", marks: [])], checked: false)
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
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .checklist, .paragraph])
        XCTAssertEqual(
            snapshot.document.blocks[1],
            .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "First", marks: [])], checked: false)
                ]
            )
        )
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Body", marks: [])])
        XCTAssertEqual(snapshot.plainText, "Title\n- [ ] First\nBody")
    }

    private func makeViewModel(from document: NotesSemanticDocument) throws -> NativeNoteEditorViewModel {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        return viewModel
    }

    private func makeViewModelForBodyParagraph(_ bodyText: String) throws -> NativeNoteEditorViewModel {
        try makeViewModel(
            from: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: bodyText, marks: [])])
                ]
            )
        )
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
