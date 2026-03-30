#if os(iOS)
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurfaceEditingTests {
    func testOrdinaryCharacterPreflightBypassesSharedStructuralMutationLayer() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel)
        let initialSelection = viewModel.selection
        let initialContent = viewModel.attributedContent
        var persistenceSnapshotCount = 0
        viewModel.onPersistenceSnapshotComputedForTesting = {
            persistenceSnapshotCount += 1
        }

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementText: "!"
        ) ?? false

        XCTAssertTrue(handled)
        XCTAssertEqual(viewModel.selection, initialSelection)
        XCTAssertEqual(viewModel.attributedContent, initialContent)
        XCTAssertEqual(persistenceSnapshotCount, 0)
    }

    func testTrailingSpaceListTriggerIsHandledBySharedStructuralMutationLayer() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "-", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(viewModel: viewModel)
        textView.selectedRange = NSRange(location: textView.text.utf16.count, length: 0)

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange,
            replacementText: " "
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .unorderedList])
        XCTAssertEqual(snapshot.plainText, "Title\n- ")
    }

    func testTrailingSpaceListTriggerUndoRestoresPlainParagraphTriggerText() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "-", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            makeKeyAndVisible: true
        )
        textView.selectedRange = NSRange(location: textView.text.utf16.count, length: 0)

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange,
            replacementText: " "
        ) ?? true

        XCTAssertFalse(handled)
        XCTAssertEqual(viewModel.currentPersistenceSnapshot().document.blocks.map(\.type), [.title, .unorderedList])

        try XCTUnwrap(textView.undoManager).undo()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let undoneSnapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(undoneSnapshot.document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertEqual(undoneSnapshot.document.blocks[1].content, [.init(text: "- ", marks: [])])
        XCTAssertEqual(undoneSnapshot.plainText, "Title\n- ")
    }

    func testTrailingSpaceChecklistTriggerIsHandledBySharedStructuralMutationLayer() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "[]", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(viewModel: viewModel)
        textView.selectedRange = NSRange(location: textView.text.utf16.count, length: 0)

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange,
            replacementText: " "
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .checklist])
        XCTAssertEqual(snapshot.plainText, "Title\n- [ ] ")
    }

    func testTrailingSpaceChecklistTriggerUndoRestoresPlainParagraphTriggerText() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "[]", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            makeKeyAndVisible: true
        )
        textView.selectedRange = NSRange(location: textView.text.utf16.count, length: 0)

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange,
            replacementText: " "
        ) ?? true

        XCTAssertFalse(handled)
        XCTAssertEqual(viewModel.currentPersistenceSnapshot().document.blocks.map(\.type), [.title, .checklist])

        try XCTUnwrap(textView.undoManager).undo()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let undoneSnapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(undoneSnapshot.document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertEqual(undoneSnapshot.document.blocks[1].content, [.init(text: "[] ", marks: [])])
        XCTAssertEqual(undoneSnapshot.plainText, "Title\n[] ")
    }
}
#endif
