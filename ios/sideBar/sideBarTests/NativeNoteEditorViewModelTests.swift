import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorViewModelTests: XCTestCase {
    func testApplyFormattingBoldTogglesInlineIntentOnSelection() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
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

    func testApplyFormattingBoldTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.bold)
        let enabledIntents = viewModel.selection.typingAttributes(in: viewModel.attributedContent).inlinePresentationIntent ?? []
        XCTAssertTrue(enabledIntents.contains(.stronglyEmphasized))

        viewModel.applyFormatting(.bold)
        let disabledIntents = viewModel.selection.typingAttributes(in: viewModel.attributedContent).inlinePresentationIntent ?? []
        XCTAssertFalse(disabledIntents.contains(.stronglyEmphasized))
    }

    func testHandleContentChangeSetsUnsavedStateAndMarkSavedClearsIt() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.autosaveDelay = 0.3
        viewModel.loadText("hello")
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

        viewModel.markSaved(plainText: viewModel.currentPlainText())
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testSelectionLineSpanCoversInsertionAndMultiLineRanges() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.attributedContent = AttributedString("line1\nline2\nline3")

        let line2Start = viewModel.attributedContent.index(viewModel.attributedContent.startIndex, offsetByCharacters: 6)
        viewModel.selection = AttributedTextSelection(range: line2Start..<line2Start)
        XCTAssertEqual(viewModel.selectionLineSpan(in: viewModel.attributedContent), 1...1)

        let line3Start = viewModel.attributedContent.index(viewModel.attributedContent.startIndex, offsetByCharacters: 12)
        let line3Next = viewModel.attributedContent.index(afterCharacter: line3Start)
        viewModel.selection = AttributedTextSelection(range: line2Start..<line3Next)
        XCTAssertEqual(viewModel.selectionLineSpan(in: viewModel.attributedContent), 1...2)
    }

    func testHandleSelectionChangeTracksSpanTransitions() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.attributedContent = AttributedString("line1\nline2")

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
        let viewModel = NativeNoteEditorViewModel()
        viewModel.autosaveDelay = 2.0
        viewModel.loadText("hello")

        let previous = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello world")
        viewModel.selection = AttributedTextSelection(range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex)
        viewModel.handleContentChange(previous: previous)

        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertEqual(viewModel.autosaveToken, 0)
    }

    func testScheduleAutosaveCancelsSupersededTask() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.autosaveDelay = 0.5
        viewModel.loadText("hello")

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
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("line one\nliteral * punctuation")

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

    private func lineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        var start = text.startIndex
        var cursor = text.startIndex

        while cursor < text.endIndex {
            if text.characters[cursor].isNewline {
                ranges.append(start..<cursor)
                start = text.index(afterCharacter: cursor)
                cursor = start
            } else {
                cursor = text.index(afterCharacter: cursor)
            }
        }

        if start <= text.endIndex {
            ranges.append(start..<text.endIndex)
        }

        return ranges
    }

}
