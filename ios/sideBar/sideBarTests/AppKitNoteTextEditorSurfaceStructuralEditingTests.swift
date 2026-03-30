#if os(macOS)
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension AppKitNoteTextEditorSurfaceTests {
    func testTrailingSpaceListTriggerIsHandledBySharedStructuralMutationLayerOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "-", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: " "
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = try XCTUnwrap(mountedStructuralEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .unorderedList])
        XCTAssertEqual(snapshot.plainText, "Title\n- ")
    }

    func testTrailingSpaceListTriggerUndoRestoresPlainParagraphTriggerTextOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "-", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: " "
        ) ?? true

        XCTAssertFalse(handled)
        XCTAssertEqual(
            mountedStructuralEditorSnapshot(from: textView)?.document.blocks.map(\.type),
            [.title, .unorderedList]
        )

        try XCTUnwrap(textView.undoManager).undo()
        drainNotesHostingRunLoop()

        let snapshot = try XCTUnwrap(mountedStructuralEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "- ", marks: [])])
        XCTAssertEqual(snapshot.plainText, "Title\n- ")
    }

    func testTrailingSpaceChecklistTriggerIsHandledBySharedStructuralMutationLayerOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "[]", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: " "
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = try XCTUnwrap(mountedEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .checklist])
        XCTAssertEqual(snapshot.plainText, "Title\n- [ ] ")
    }

    func testTrailingSpaceChecklistTriggerUndoRestoresPlainParagraphTriggerTextOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "[]", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: " "
        ) ?? true

        XCTAssertFalse(handled)
        XCTAssertEqual(
            mountedEditorSnapshot(from: textView)?.document.blocks.map(\.type),
            [.title, .checklist]
        )

        try XCTUnwrap(textView.undoManager).undo()
        drainNotesHostingRunLoop()

        let snapshot = try XCTUnwrap(mountedEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "[] ", marks: [])])
        XCTAssertEqual(snapshot.plainText, "Title\n[] ")
    }
}
#endif
