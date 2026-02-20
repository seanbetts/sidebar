import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeMarkdownEditorViewModelTests: XCTestCase {
    func testApplyFormattingBoldTogglesInlineIntentOnSelection() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello")
        let firstSelection = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: firstSelection)

        viewModel.applyFormatting(.bold)
        let firstRange = characterRange(length: 5, in: viewModel.attributedContent)
        let firstIntents = viewModel.attributedContent[firstRange].inlinePresentationIntent ?? []
        XCTAssertTrue(firstIntents.contains(.stronglyEmphasized))

        // Re-apply a fresh selection range after mutation so toggling uses valid indices.
        viewModel.selection = AttributedTextSelection(range: characterRange(length: 5, in: viewModel.attributedContent))
        viewModel.applyFormatting(.bold)
        let secondRange = characterRange(length: 5, in: viewModel.attributedContent)
        let secondIntents = viewModel.attributedContent[secondRange].inlinePresentationIntent ?? []
        XCTAssertFalse(secondIntents.contains(.stronglyEmphasized))
    }

    func testApplyFormattingHeadingSetsBlockKindForCurrentParagraph() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello\nworld")
        let insertion = viewModel.attributedContent.startIndex
        let next = viewModel.attributedContent.index(afterCharacter: insertion)
        viewModel.selection = AttributedTextSelection(range: insertion..<next)

        viewModel.applyFormatting(.heading(level: 2))
        let firstLineRange = firstLine(in: viewModel.attributedContent)

        XCTAssertEqual(viewModel.attributedContent.blockKind(in: firstLineRange), .heading2)
    }

    func testHandleContentChangeSetsUnsavedStateAndMarkSavedClearsIt() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.autosaveDelay = 0.3
        viewModel.loadMarkdown("hello")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let previous = viewModel.attributedContent

        viewModel.attributedContent = AttributedString("hello world")
        viewModel.selection = AttributedTextSelection(range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex)
        viewModel.handleContentChange(previous: previous)

        for _ in 0..<20 {
            if viewModel.hasUnsavedChanges, viewModel.autosaveToken > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertGreaterThan(viewModel.autosaveToken, 0)

        viewModel.markSaved(markdown: viewModel.currentMarkdown())
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testSelectionLineSpanCoversInsertionAndMultiLineRanges() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("line1\nline2\nline3")

        let line2Start = viewModel.attributedContent.index(viewModel.attributedContent.startIndex, offsetByCharacters: 6)
        viewModel.selection = AttributedTextSelection(range: line2Start..<line2Start)
        XCTAssertEqual(viewModel.selectionLineSpan(in: viewModel.attributedContent), 1...1)

        let line3Start = viewModel.attributedContent.index(viewModel.attributedContent.startIndex, offsetByCharacters: 12)
        let line3Next = viewModel.attributedContent.index(afterCharacter: line3Start)
        viewModel.selection = AttributedTextSelection(range: line2Start..<line3Next)
        XCTAssertEqual(viewModel.selectionLineSpan(in: viewModel.attributedContent), 1...2)
    }

    func testHandleSelectionChangeTracksSpanTransitions() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("line1\nline2")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let line1Start = viewModel.attributedContent.startIndex
        viewModel.selection = AttributedTextSelection(range: line1Start..<line1Start)
        viewModel.handleSelectionChange()
        XCTAssertEqual(viewModel.lastSelectionLineSpan, 0...0)

        let line1Next = viewModel.attributedContent.index(afterCharacter: line1Start)
        viewModel.selection = AttributedTextSelection(range: line1Next..<line1Next)
        viewModel.handleSelectionChange()
        XCTAssertEqual(viewModel.lastSelectionLineSpan, 0...0)

        let line2Start = viewModel.attributedContent.index(viewModel.attributedContent.startIndex, offsetByCharacters: 6)
        viewModel.selection = AttributedTextSelection(range: line2Start..<line2Start)
        viewModel.handleSelectionChange()
        XCTAssertEqual(viewModel.lastSelectionLineSpan, 1...1)
    }

    func testHandleContentChangeMarksUnsavedImmediately() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.autosaveDelay = 2.0
        viewModel.loadMarkdown("hello")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let previous = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello world")
        viewModel.selection = AttributedTextSelection(range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex)
        viewModel.handleContentChange(previous: previous)

        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertEqual(viewModel.autosaveToken, 0)
    }

    func testScheduleAutosaveCancelsSupersededTask() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.autosaveDelay = 0.5
        viewModel.loadMarkdown("hello")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let initial = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello1")
        viewModel.selection = AttributedTextSelection(range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex)
        viewModel.handleContentChange(previous: initial)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let secondPrevious = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello2")
        viewModel.selection = AttributedTextSelection(range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex)
        viewModel.handleContentChange(previous: secondPrevious)

        try? await Task.sleep(nanoseconds: 750_000_000)

        XCTAssertEqual(viewModel.autosaveToken, 1)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testPlainPunctuationDoesNotBecomeInlineMarker() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("line one\nliteral * punctuation")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let text = String(viewModel.attributedContent.characters)
        guard let markerIndex = text.firstIndex(of: "*") else {
            XCTFail("Expected a literal marker character")
            return
        }
        let markerOffset = text.distance(from: text.startIndex, to: markerIndex)
        let attributedIndex = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: markerOffset
        )
        let markerRun = viewModel.attributedContent.runs.first { run in
            run.range.contains(attributedIndex)
        }

        XCTAssertNotNil(markerRun)
        XCTAssertNotEqual(markerRun?.inlineMarker, true)
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
