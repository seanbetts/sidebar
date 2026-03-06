import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorViewModelTests: XCTestCase {
    func testApplyFormattingBoldTogglesSelectedRangeFontTraits() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.bold)
        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: range))

        viewModel.selection = AttributedTextSelection(range: noteCharacterRange(length: 5, in: viewModel.attributedContent))
        viewModel.applyFormatting(.bold)
        let updatedRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        XCTAssertFalse(noteRangeHasBoldTrait(viewModel.attributedContent, range: updatedRange))
    }

    func testApplyFormattingBoldTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.bold)
        XCTAssertTrue(noteTypingTraits(from: viewModel.selection.typingAttributes(in: viewModel.attributedContent)).bold)

        viewModel.applyFormatting(.bold)
        XCTAssertFalse(noteTypingTraits(from: viewModel.selection.typingAttributes(in: viewModel.attributedContent)).bold)
    }

    func testHandleContentChangeSetsUnsavedStateAndMarkSavedClearsIt() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.autosaveDelay = 0.3
        viewModel.loadText("hello")
        let previous = viewModel.attributedContent

        viewModel.attributedContent = AttributedString("hello world")
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
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

        let line2Start = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: 6
        )
        viewModel.selection = AttributedTextSelection(range: line2Start..<line2Start)
        XCTAssertEqual(viewModel.selectionLineSpan(in: viewModel.attributedContent), 1...1)

        let line3Start = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: 12
        )
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

        let line2Start = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: 6
        )
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
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
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
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
        viewModel.handleContentChange(previous: initial)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let secondPrevious = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello2")
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
        viewModel.handleContentChange(previous: secondPrevious)

        try? await Task.sleep(nanoseconds: 750_000_000)

        XCTAssertEqual(viewModel.autosaveToken, 1)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
}
