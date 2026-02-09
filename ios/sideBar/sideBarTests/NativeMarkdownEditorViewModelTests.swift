import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeMarkdownEditorViewModelTests: XCTestCase {
    func testApplyFormattingBoldTogglesInlineIntentOnSelection() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello")
        let selectedRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: selectedRange)

        viewModel.applyFormatting(.bold)
        let firstIntents = viewModel.attributedContent[selectedRange].inlinePresentationIntent ?? []
        XCTAssertTrue(firstIntents.contains(.stronglyEmphasized))

        viewModel.applyFormatting(.bold)
        let secondIntents = viewModel.attributedContent[selectedRange].inlinePresentationIntent ?? []
        XCTAssertFalse(secondIntents.contains(.stronglyEmphasized))
    }

    func testApplyFormattingHeadingSetsBlockKindForCurrentParagraph() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello\nworld")
        let insertion = viewModel.attributedContent.startIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.heading(level: 2))
        let firstLineRange = firstLine(in: viewModel.attributedContent)

        XCTAssertEqual(viewModel.attributedContent.blockKind(in: firstLineRange), .heading2)
    }

    func testHandleContentChangeSetsUnsavedStateAndMarkSavedClearsIt() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.autosaveDelay = 0.3
        viewModel.loadMarkdown("hello")
        let previous = viewModel.attributedContent

        viewModel.attributedContent = AttributedString("hello world")
        viewModel.selection = AttributedTextSelection(range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex)
        viewModel.handleContentChange(previous: previous)

        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertGreaterThan(viewModel.autosaveToken, 0)

        viewModel.markSaved(markdown: viewModel.currentMarkdown())
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    private func characterRange(
        length: Int,
        in text: AttributedString
    ) -> Range<AttributedString.Index> {
        let start = text.startIndex
        let end = text.index(start, offsetByCharacters: length)
        return start..<end
    }

    private func firstLine(in text: AttributedString) -> Range<AttributedString.Index> {
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text.characters[cursor].isNewline {
                return text.startIndex..<cursor
            }
            cursor = text.index(afterCharacter: cursor)
        }
        return text.startIndex..<text.endIndex
    }
}
