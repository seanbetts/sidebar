#if os(iOS)
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteTextEditorSurfaceEditingTests: NotesDetailViewHostingTestCase {
    func testUIKitSelectionChangesFlowBackIntoCanonicalSelectionUsingUTF16Offsets() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("A👍🏽B"),
            plainText: "A👍🏽B"
        )
        let coordinator = UIKitNoteTextEditorSurface.Coordinator(viewModel: viewModel)
        let textView = UITextView()
        textView.attributedText = NSAttributedString(string: "A👍🏽B")
        textView.delegate = coordinator
        textView.selectedRange = NSRange(location: 5, length: 0)
        textView.delegate?.textViewDidChangeSelection?(textView)
        assertUIKitInsertionPointUTF16Offset(
            viewModel.selection,
            in: viewModel.attributedContent,
            equals: 5
        )
    }

    func testUIKitTextChangesFlowBackIntoCanonicalContent() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel)
        let previous = viewModel.attributedContent
        textView.text = "Hello updated"
        textView.delegate?.textViewDidChange?(textView)
        XCTAssertEqual(String(viewModel.attributedContent.characters), "Hello updated")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertNotEqual(viewModel.attributedContent, previous)
    }

    func testCanonicalBoldFormattingRendersIntoUIKitAttributedText() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Bold"),
            plainText: "Bold"
        )
        let range = noteCharacterRange(length: 4, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)
        viewModel.applyFormatting(.bold)
        let textView = try mountTextView(viewModel: viewModel)
        let font = try XCTUnwrap(textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testInsertionPointFormattingToggleUpdatesUIKitTypingAttributes() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Title\nHello"),
            plainText: "Title\nHello"
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        let textView = try mountTextView(viewModel: viewModel)
        XCTAssertFalse(
            try XCTUnwrap(textView.typingAttributes[.font] as? UIFont)
                .fontDescriptor
                .symbolicTraits
                .contains(.traitBold)
        )
        viewModel.applyFormatting(.bold)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let font = try XCTUnwrap(textView.typingAttributes[.font] as? UIFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testReturnKeyIsHandledBySharedBlockTransitionLayer() throws {
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
        let insertionPoint = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertionPoint..<insertionPoint)
        let textView = try mountTextView(viewModel: viewModel)
        textView.selectedRange = viewModel.utf16SelectedRange(in: viewModel.attributedContent)

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange,
            replacementText: "\n"
        ) ?? true

        XCTAssertFalse(handled)
        textView.insertText("Body")
        XCTAssertEqual(
            viewModel.currentPersistenceSnapshot().document.blocks.map(\.type),
            [.title, .heading, .paragraph]
        )
    }

    func testUIKitSurfaceUsesDynamicLabelColorForExistingAndNewText() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel)
        let renderedColor = try XCTUnwrap(
            textView.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        )
        let typingColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? UIColor)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(
            renderedColor.resolvedColor(with: darkTraits),
            UIColor.label.resolvedColor(with: darkTraits)
        )
        XCTAssertEqual(
            typingColor.resolvedColor(with: darkTraits),
            UIColor.label.resolvedColor(with: darkTraits)
        )
    }

    func testUIKitFormattedEditsDoNotStripExistingBoldFormatting() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Bold"),
            plainText: "Bold"
        )
        let range = noteCharacterRange(length: 4, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)
        viewModel.applyFormatting(.bold)
        let textView = try mountTextView(viewModel: viewModel)
        let updated = NSMutableAttributedString(attributedString: textView.attributedText)
        updated.append(NSAttributedString(string: "!"))
        textView.attributedText = updated
        textView.selectedRange = NSRange(location: updated.length, length: 0)
        textView.delegate?.textViewDidChange?(textView)
        let updatedRange = noteCharacterRange(length: 4, in: viewModel.attributedContent)
        XCTAssertEqual(String(viewModel.attributedContent.characters), "Bold!")
        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: updatedRange))
    }

    func testPendingCaretTargetsStillLandAtCorrectInsertionPointWhenUIKitSurfaceMounts() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "A👍🏽B"))
        let nativeViewModel = NativeNoteEditorViewModel()
        context.editorViewModel.enterEditMode(at: .characterOffset(5))
        _ = AttributedNoteEditorContainer.loadNoteIfNeeded(
            editorViewModel: context.editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: nil
        )
        let textView = try mountTextView(viewModel: nativeViewModel)
        XCTAssertEqual(textView.selectedRange, NSRange(location: 5, length: 0))
    }
}

#endif
