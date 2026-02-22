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

    func testApplyFormattingBoldTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.bold)
        let enabledIntents = viewModel.selection.typingAttributes(in: viewModel.attributedContent).inlinePresentationIntent ?? []
        XCTAssertTrue(enabledIntents.contains(.stronglyEmphasized))

        viewModel.applyFormatting(.bold)
        let disabledIntents = viewModel.selection.typingAttributes(in: viewModel.attributedContent).inlinePresentationIntent ?? []
        XCTAssertFalse(disabledIntents.contains(.stronglyEmphasized))
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

    func testApplyFormattingTaskListSetsTaskBlockKindForCurrentParagraph() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello")
        let insertion = viewModel.attributedContent.startIndex
        let next = viewModel.attributedContent.index(afterCharacter: insertion)
        viewModel.selection = AttributedTextSelection(range: insertion..<next)

        viewModel.applyFormatting(.taskList)
        let firstLineRange = firstLine(in: viewModel.attributedContent)

        XCTAssertEqual(viewModel.attributedContent.blockKind(in: firstLineRange), .taskUnchecked)
    }

    func testIndentAndOutdentListItemsAdjustDepthDeterministically() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello")
        let insertion = viewModel.attributedContent.startIndex
        let next = viewModel.attributedContent.index(afterCharacter: insertion)
        viewModel.selection = AttributedTextSelection(range: insertion..<next)
        viewModel.applyFormatting(.bulletList)

        var lineRange = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent[lineRange].listDepth, 1)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: lineRange), .bulletList)

        lineRange = firstLine(in: viewModel.attributedContent)
        let indentStart = lineRange.lowerBound
        let indentNext = viewModel.attributedContent.index(afterCharacter: indentStart)
        viewModel.selection = AttributedTextSelection(range: indentStart..<indentNext)
        viewModel.indentListItems()
        lineRange = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent[lineRange].listDepth, 2)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: lineRange), .bulletList)

        lineRange = firstLine(in: viewModel.attributedContent)
        let outdentStart = lineRange.lowerBound
        let outdentNext = viewModel.attributedContent.index(afterCharacter: outdentStart)
        viewModel.selection = AttributedTextSelection(range: outdentStart..<outdentNext)
        viewModel.outdentListItems()
        lineRange = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent[lineRange].listDepth, 1)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: lineRange), .bulletList)

        lineRange = firstLine(in: viewModel.attributedContent)
        let finalOutdentStart = lineRange.lowerBound
        let finalOutdentNext = viewModel.attributedContent.index(afterCharacter: finalOutdentStart)
        viewModel.selection = AttributedTextSelection(range: finalOutdentStart..<finalOutdentNext)
        viewModel.outdentListItems()
        lineRange = firstLine(in: viewModel.attributedContent)
        XCTAssertNil(viewModel.attributedContent[lineRange].listDepth)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: lineRange), .paragraph)
    }

    func testApplyFormattingIndentAndOutdentRoutesThroughCommandLayer() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello")
        let insertion = viewModel.attributedContent.startIndex
        let next = viewModel.attributedContent.index(afterCharacter: insertion)
        viewModel.selection = AttributedTextSelection(range: insertion..<next)
        viewModel.applyFormatting(.bulletList)

        var lineRange = firstLine(in: viewModel.attributedContent)
        let indentStart = lineRange.lowerBound
        let indentNext = viewModel.attributedContent.index(afterCharacter: indentStart)
        viewModel.selection = AttributedTextSelection(range: indentStart..<indentNext)

        viewModel.applyFormatting(.indentList)
        lineRange = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent[lineRange].listDepth, 2)

        let outdentStart = lineRange.lowerBound
        let outdentNext = viewModel.attributedContent.index(afterCharacter: outdentStart)
        viewModel.selection = AttributedTextSelection(range: outdentStart..<outdentNext)

        viewModel.applyFormatting(.outdentList)
        lineRange = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent[lineRange].listDepth, 1)
    }

    func testIndentListItemsAppliesToEachSelectedParagraphAcrossMixedListKinds() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("Bullet line\nTask line\nPlain line")
        let initialRanges = lineRanges(in: viewModel.attributedContent)
        XCTAssertEqual(initialRanges.count, 3)

        viewModel.attributedContent[initialRanges[0]].blockKind = .bulletList
        viewModel.attributedContent[initialRanges[0]].listDepth = 1
        viewModel.attributedContent[initialRanges[1]].blockKind = .taskUnchecked
        viewModel.attributedContent[initialRanges[1]].listDepth = 1

        let selectionRanges = lineRanges(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(
            range: selectionRanges[0].lowerBound..<selectionRanges[1].upperBound
        )
        viewModel.indentListItems()

        let updatedRanges = lineRanges(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedRanges[0]), .bulletList)
        XCTAssertEqual(viewModel.attributedContent[updatedRanges[0]].listDepth, 2)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedRanges[1]), .taskUnchecked)
        XCTAssertEqual(viewModel.attributedContent[updatedRanges[1]].listDepth, 2)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedRanges[2]), .paragraph)
        XCTAssertNil(viewModel.attributedContent[updatedRanges[2]].listDepth)
    }

    func testOutdentListItemsConvertsEachSelectedDepthOneParagraphToParagraph() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("Bullet line\nOrdered line\nPlain line")
        let initialRanges = lineRanges(in: viewModel.attributedContent)
        XCTAssertEqual(initialRanges.count, 3)

        viewModel.attributedContent[initialRanges[0]].blockKind = .bulletList
        viewModel.attributedContent[initialRanges[0]].listDepth = 1
        viewModel.attributedContent[initialRanges[1]].blockKind = .orderedList
        viewModel.attributedContent[initialRanges[1]].listDepth = 1

        let selectionRanges = lineRanges(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(
            range: selectionRanges[0].lowerBound..<selectionRanges[1].upperBound
        )
        viewModel.outdentListItems()

        let updatedRanges = lineRanges(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedRanges[0]), .paragraph)
        XCTAssertNil(viewModel.attributedContent[updatedRanges[0]].listDepth)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedRanges[1]), .paragraph)
        XCTAssertNil(viewModel.attributedContent[updatedRanges[1]].listDepth)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedRanges[2]), .paragraph)
        XCTAssertNil(viewModel.attributedContent[updatedRanges[2]].listDepth)
    }

    func testHandleListDepthKeyboardShortcutReturnsFalseForNonListSelection() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("Plain line")
        let line = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: line.lowerBound..<line.upperBound)

        let handled = viewModel.handleListDepthKeyboardShortcut(outdent: false)

        XCTAssertFalse(handled)
        let updatedLine = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedLine), .paragraph)
        XCTAssertNil(viewModel.attributedContent[updatedLine].listDepth)
    }

    func testHandleListDepthKeyboardShortcutOutdentsWhenListSelected() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("List item")
        var line = firstLine(in: viewModel.attributedContent)
        viewModel.attributedContent[line].blockKind = .bulletList
        viewModel.attributedContent[line].listDepth = 2
        line = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: line.lowerBound..<line.upperBound)

        let handled = viewModel.handleListDepthKeyboardShortcut(outdent: true)

        XCTAssertTrue(handled)
        line = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: line), .bulletList)
        XCTAssertEqual(viewModel.attributedContent[line].listDepth, 1)
    }

    func testUpdatePrefixVisibilityRemovesInjectedListMarkersWhenDisabled() async {
        let viewModel = NativeMarkdownEditorViewModel()
        var content = AttributedString("• Item")
        let markerEnd = content.index(content.startIndex, offsetByCharacters: 2)
        let markerRange = content.startIndex..<markerEnd
        let textRange = markerEnd..<content.endIndex
        content[markerRange].listMarker = true
        content[markerRange].blockKind = .bulletList
        content[markerRange].listDepth = 1
        content[textRange].blockKind = .bulletList
        content[textRange].listDepth = 1

        viewModel.attributedContent = content
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        viewModel.usesInjectedListMarkers = false

        viewModel.updatePrefixVisibility()

        XCTAssertEqual(String(viewModel.attributedContent.characters), "Item")
        XCTAssertFalse(viewModel.attributedContent.runs.contains { $0.listMarker == true })
    }

    func testApplyFormattingStrikethroughTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.strikethrough)
        XCTAssertEqual(viewModel.selection.typingAttributes(in: viewModel.attributedContent).strikethroughStyle, .single)

        viewModel.applyFormatting(.strikethrough)
        XCTAssertNil(viewModel.selection.typingAttributes(in: viewModel.attributedContent).strikethroughStyle)
    }

    func testApplyFormattingHorizontalRuleInsertsHorizontalRuleBlock() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.horizontalRule)

        let text = String(viewModel.attributedContent.characters)
        XCTAssertTrue(text.contains("---"))

        let ruleStartIndex = viewModel.attributedContent.index(
            viewModel.attributedContent.endIndex,
            offsetByCharacters: -3
        )
        let ruleRange = ruleStartIndex..<viewModel.attributedContent.endIndex
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: ruleRange), .horizontalRule)
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
