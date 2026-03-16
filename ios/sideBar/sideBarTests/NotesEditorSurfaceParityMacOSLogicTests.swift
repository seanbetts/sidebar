import XCTest
import SwiftUI
@testable import sideBar

#if os(macOS)
@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesEditorSurfaceParityMacOSLogicTests: XCTestCase {
    func testSelectionOnlyChangesDoNotAdvanceRenderGenerationOrInvalidatePersistenceCacheOnMacOS() throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "Hello\nWorld")
        let canonicalContent = try XCTUnwrap(NotesSemanticDocumentCodec.encode(document))
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalContent,
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )

        _ = viewModel.currentPersistenceSnapshot()
        var persistenceSnapshotComputations = 0
        viewModel.onPersistenceSnapshotComputedForTesting = {
            persistenceSnapshotComputations += 1
        }
        let initialRenderGeneration = viewModel.renderGeneration
        let insertionPoint = viewModel.index(forCharacterOffset: 3, in: viewModel.attributedContent)

        viewModel.selection = AttributedTextSelection(range: insertionPoint..<insertionPoint)
        viewModel.handleSelectionChange()
        _ = viewModel.currentPersistenceSnapshot()

        XCTAssertEqual(viewModel.renderGeneration, initialRenderGeneration)
        XCTAssertEqual(persistenceSnapshotComputations, 0)
    }

    func testTrailingEmptyParagraphTypingAttributesStayPlainOnMacOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
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

        let typingAttributes = viewModel.typingAttributesForInsertion(in: viewModel.attributedContent)

        XCTAssertEqual(NoteTextBlockAttribute.blockType(from: typingAttributes.noteBlock), .paragraph)
        XCTAssertFalse(noteTypingTraits(from: typingAttributes).bold)
    }
}
#endif
