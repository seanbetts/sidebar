import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorInlineFormattingTests: XCTestCase {
    func testApplyFormattingItalicTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.italic)
        XCTAssertTrue(noteTypingTraits(from: viewModel.selection.typingAttributes(in: viewModel.attributedContent)).italic)

        viewModel.applyFormatting(.italic)
        XCTAssertFalse(noteTypingTraits(from: viewModel.selection.typingAttributes(in: viewModel.attributedContent)).italic)
    }

    func testApplyFormattingUnderlineTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.underline)
        XCTAssertEqual(
            viewModel.selection.typingAttributes(in: viewModel.attributedContent).underlineStyle,
            .single
        )

        viewModel.applyFormatting(.underline)
        XCTAssertNil(
            viewModel.selection.typingAttributes(in: viewModel.attributedContent).underlineStyle
        )
    }

    func testApplyFormattingStrikethroughTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.strikethrough)
        XCTAssertEqual(
            viewModel.selection.typingAttributes(in: viewModel.attributedContent).strikethroughStyle,
            .single
        )

        viewModel.applyFormatting(.strikethrough)
        XCTAssertNil(
            viewModel.selection.typingAttributes(in: viewModel.attributedContent).strikethroughStyle
        )
    }

    func testApplyFormattingBoldStylesSelectedRangeImmediately() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.bold)

        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: range))
    }

    func testApplyFormattingItalicStylesSelectedRangeImmediately() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.italic)

        XCTAssertTrue(noteRangeHasItalicTrait(viewModel.attributedContent, range: range))
    }

    func testApplyFormattingStrikethroughStylesSelectedRangeImmediately() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.strikethrough)

        XCTAssertTrue(noteRangeIsStruckThrough(viewModel.attributedContent, range: range))
    }

    func testApplyFormattingPreservesExistingTraitsWhenAddingSecondStyle() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.bold)
        viewModel.selection = AttributedTextSelection(range: noteCharacterRange(length: 5, in: viewModel.attributedContent))
        viewModel.applyFormatting(.italic)

        let updatedRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: updatedRange))
        XCTAssertTrue(noteRangeHasItalicTrait(viewModel.attributedContent, range: updatedRange))
    }
}
