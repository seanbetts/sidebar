#if os(iOS)
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurfaceEditingTests {
    func testChecklistDocumentRendersAttachmentMarkersInUIKitEditorSurface() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Task", marks: [])], checked: false)
                    ]
                )
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )

        let textView = try mountTextView(viewModel: viewModel)

        XCTAssertNotNil(textView.attributedText.attribute(.attachment, at: 0, effectiveRange: nil))
        XCTAssertEqual(textView.selectedRange.length, 0)
    }

    func testUIKitChecklistSelectionChangesMapDisplayOffsetsBackIntoCanonicalSelection() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Task", marks: [])], checked: false)
                    ]
                )
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )

        let textView = try mountTextView(viewModel: viewModel, makeKeyAndVisible: true)
        XCTAssertTrue(textView.becomeFirstResponder())
        simulateUIKitSelectionChange(on: textView, to: NSRange(location: 2, length: 0))

        assertUIKitInsertionPointUTF16Offset(
            viewModel.selection,
            in: viewModel.attributedContent,
            equals: 6
        )
    }

    func testUIKitChecklistTextChangesExpandDisplayMarkersBackIntoCanonicalContent() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Task", marks: [])], checked: false)
                    ]
                )
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )

        let textView = try mountTextView(viewModel: viewModel)
        let updated = NSMutableAttributedString(attributedString: textView.attributedText)
        updated.append(NSAttributedString(string: "!"))
        textView.attributedText = updated
        textView.selectedRange = NSRange(location: updated.length, length: 0)
        textView.delegate?.textViewDidChange?(textView)

        await waitUntil(timeout: .seconds(1)) {
            viewModel.currentPersistenceSnapshot().document.blocks.first?.children?.first?.content
                == [.init(text: "Task!", marks: [])]
        }

        XCTAssertEqual(
            viewModel.currentPersistenceSnapshot().document.blocks.first?.children?.first?.content,
            [.init(text: "Task!", marks: [])]
        )
        assertUIKitInsertionPointUTF16Offset(
            viewModel.selection,
            in: viewModel.attributedContent,
            equals: 11
        )
    }

    func testEscapeKeyCommandFromUIKitEditorSurfaceInvokesExitCallback() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        var escapeCount = 0

        let textView = try mountTextView(
            viewModel: viewModel,
            makeKeyAndVisible: true,
            onEscape: { escapeCount += 1 }
        )
        XCTAssertTrue(textView.becomeFirstResponder())

        textView.handleEscapeCommand()

        XCTAssertEqual(escapeCount, 1)
    }
}

#endif
