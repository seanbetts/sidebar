import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#endif
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

    func testTableLayoutDoesNotAccumulateIndentAcrossPrefixVisibilityUpdates() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown(
            """
            | Feature | Status |
            | --- | --- |
            | Tables | In Progress |
            """
        )
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        guard let tableLineRange = firstTableLine(in: viewModel.attributedContent),
              let initialStyle = viewModel.attributedContent[tableLineRange].paragraphStyle else {
            XCTFail("Expected table row paragraph style")
            return
        }

        let initialHeadIndent = initialStyle.headIndent
        let initialTailIndent = initialStyle.tailIndent

        for _ in 0..<3 {
            viewModel.updatePrefixVisibility()
            for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        guard let updatedStyle = viewModel.attributedContent[tableLineRange].paragraphStyle else {
            XCTFail("Expected updated table row paragraph style")
            return
        }

        XCTAssertEqual(updatedStyle.headIndent, initialHeadIndent)
        XCTAssertEqual(updatedStyle.tailIndent, initialTailIndent)
    }

    func testDisplayTextKeepsHorizontalRuleTextInEditMode() {
        var text = AttributedString("---")
        let range = text.startIndex..<text.endIndex
        text[range].blockKind = .horizontalRule

        let editable = displayText(for: text, isEditable: true)

        XCTAssertEqual(editable.string, "---")
        XCTAssertNil(editable.attribute(.attachment, at: 0, effectiveRange: nil))
    }

    func testDisplayTextRendersHorizontalRuleAsAttachmentInReadMode() {
        var text = AttributedString("---")
        let range = text.startIndex..<text.endIndex
        text[range].blockKind = .horizontalRule

        let readOnly = displayText(for: text, isEditable: false)

        XCTAssertNotNil(readOnly.attribute(.attachment, at: 0, effectiveRange: nil))
    }

    func testOrderedListOrdinalsResetAfterBreak() async {
        let viewModel = NativeMarkdownEditorViewModel()
        let contexts: [NativeMarkdownEditorViewModel.OrderedListLineContext] = [
            .init(isOrdered: true, depth: 1, identity: 42),
            .init(isOrdered: true, depth: 1, identity: 42),
            .init(isOrdered: false, depth: 1, identity: nil),
            .init(isOrdered: true, depth: 1, identity: 42)
        ]

        let ordinals = viewModel.orderedListOrdinals(for: contexts)
        XCTAssertEqual(ordinals[0], 1)
        XCTAssertEqual(ordinals[1], 2)
        XCTAssertEqual(ordinals[3], 1)
    }

#if os(iOS)
    func testHiddenHeadingPrefixRetainsReadableFontSize() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("# Heading\nParagraph")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let content = String(viewModel.attributedContent.characters)
        guard let paragraphStart = content.range(of: "Paragraph")?.lowerBound else {
            XCTFail("Expected paragraph line")
            return
        }
        let paragraphOffset = content.distance(from: content.startIndex, to: paragraphStart)
        let paragraphIndex = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: paragraphOffset
        )
        viewModel.selection = AttributedTextSelection(range: paragraphIndex..<paragraphIndex)
        viewModel.handleSelectionChange()
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let updated = String(viewModel.attributedContent.characters)
        guard let hashIndex = updated.firstIndex(of: "#") else {
            XCTFail("Expected heading prefix marker")
            return
        }
        let hashOffset = updated.distance(from: updated.startIndex, to: hashIndex)
        let nsText = NSAttributedString(viewModel.attributedContent)
        guard let font = nsText.attribute(.font, at: hashOffset, effectiveRange: nil) as? UIFont else {
            XCTFail("Expected UIKit font for heading prefix")
            return
        }
        XCTAssertGreaterThan(font.pointSize, 1.0)
    }

    func testHiddenInlineMarkersRetainReadableFontSize() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("**bold**\nnext line")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let content = String(viewModel.attributedContent.characters)
        guard let nextLineStart = content.range(of: "next line")?.lowerBound else {
            XCTFail("Expected second line")
            return
        }
        let nextLineOffset = content.distance(from: content.startIndex, to: nextLineStart)
        let nextLineIndex = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: nextLineOffset
        )
        viewModel.selection = AttributedTextSelection(range: nextLineIndex..<nextLineIndex)
        viewModel.handleSelectionChange()
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let updated = String(viewModel.attributedContent.characters)
        guard let markerIndex = updated.firstIndex(of: "*") else {
            XCTFail("Expected inline marker")
            return
        }
        let markerOffset = updated.distance(from: updated.startIndex, to: markerIndex)
        let nsText = NSAttributedString(viewModel.attributedContent)
        guard let font = nsText.attribute(.font, at: markerOffset, effectiveRange: nil) as? UIFont else {
            XCTFail("Expected UIKit font for inline marker")
            return
        }
        XCTAssertGreaterThan(font.pointSize, 1.0)
    }
#endif

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

    private func firstTableLine(in text: AttributedString) -> Range<AttributedString.Index>? {
        var lineStart = text.startIndex
        var cursor = text.startIndex

        while cursor < text.endIndex {
            if text.characters[cursor].isNewline {
                let lineRange = lineStart..<cursor
                if String(text[lineRange].characters).contains("\t") {
                    return lineRange
                }
                lineStart = text.index(afterCharacter: cursor)
            }
            cursor = text.index(afterCharacter: cursor)
        }

        if lineStart <= text.endIndex {
            let lineRange = lineStart..<text.endIndex
            if String(text[lineRange].characters).contains("\t") {
                return lineRange
            }
        }

        return nil
    }

}
