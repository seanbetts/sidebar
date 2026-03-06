import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorRegressionTests: XCTestCase {
    func testHandleContentChangePreservesUnderlineStyling() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("plain text")
        let lineRange = noteCharacterRange(length: 10, in: viewModel.attributedContent)
        viewModel.attributedContent[lineRange].underlineStyle = .single

        let previous = viewModel.attributedContent
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.handleContentChange(previous: previous)

        XCTAssertTrue(noteRangeIsUnderlined(viewModel.attributedContent, range: lineRange))
    }

    func testHandleContentChangeLeavesSelectedBoldFormattingIntact() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let lineRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        let previous = viewModel.attributedContent

        viewModel.selection = AttributedTextSelection(range: lineRange)
        viewModel.applyFormatting(.bold)
        viewModel.handleContentChange(previous: previous)

        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: lineRange))
    }

    func testHandleContentChangeLeavesSelectedItalicFormattingIntact() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let lineRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        let previous = viewModel.attributedContent

        viewModel.selection = AttributedTextSelection(range: lineRange)
        viewModel.applyFormatting(.italic)
        viewModel.handleContentChange(previous: previous)

        XCTAssertTrue(noteRangeHasItalicTrait(viewModel.attributedContent, range: lineRange))
    }

    func testSelectedFormattingToggleOffClearsLiveDocumentState() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let lineRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)

        viewModel.selection = AttributedTextSelection(range: lineRange)
        viewModel.applyFormatting(.bold)
        viewModel.selection = AttributedTextSelection(range: noteCharacterRange(length: 5, in: viewModel.attributedContent))
        viewModel.applyFormatting(.bold)

        let updatedRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        XCTAssertFalse(noteRangeHasBoldTrait(viewModel.attributedContent, range: updatedRange))
    }
}
