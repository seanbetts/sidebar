import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteFormattingBehaviorTests: XCTestCase {
    func testPromoteHeadingKeepsSelectedRange() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello world")

        let start = viewModel.attributedContent.startIndex
        let end = viewModel.attributedContent.index(start, offsetByCharacters: 5)
        viewModel.selection = AttributedTextSelection(range: start..<end)

        let before = selectionOffsets(in: viewModel)
        viewModel.applyFormatting(.promoteHeading)
        let after = selectionOffsets(in: viewModel)

        XCTAssertEqual(before, after)
    }

    func testCanAdjustListDepthWhenParagraphIsListBlock() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Item")
        var line = firstLineRange(in: viewModel.attributedContent)
        viewModel.attributedContent[line].blockKind = .bulletList
        viewModel.attributedContent[line].listDepth = 1
        line = firstLineRange(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: line.lowerBound..<line.upperBound)

        XCTAssertTrue(viewModel.canAdjustListDepth())
    }

    func testBlockquoteDisplaysReadMarkerAndExportsCleanMarkdown() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("> Quoted")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(String(viewModel.attributedContent.characters).hasPrefix("│ "))
        XCTAssertEqual(serializedNoteContent(viewModel), "> Quoted")
    }

    func testHorizontalRuleInsertionProducesMarkdownRule() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("alpha")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.horizontalRule)

        XCTAssertEqual(serializedNoteContent(viewModel), "alpha\n\n---")
    }

    func testHeadingParagraphStyleRetainsVerticalSpacing() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("## Heading\nBody")

        let firstLine = firstLineRange(in: viewModel.attributedContent)
        let style = viewModel.attributedContent[firstLine].paragraphStyle
        XCTAssertNotNil(style)
        XCTAssertGreaterThan(style?.paragraphSpacingBefore ?? 0, 0)
        XCTAssertGreaterThan(style?.paragraphSpacing ?? 0, 0)
    }

    func testSpacingBeforeCollapsesAgainstPreviousParagraphSpacing() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Body\n## Heading")

        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let ranges = allLineRanges(in: viewModel.attributedContent)
        XCTAssertEqual(ranges.count, 2)

        let bodyStyle = viewModel.attributedContent[ranges[0]].paragraphStyle
        let headingStyle = viewModel.attributedContent[ranges[1]].paragraphStyle
        XCTAssertNotNil(bodyStyle)
        XCTAssertNotNil(headingStyle)

        // CSS-equivalent collapse: max(body bottom 0.5rem, heading top 1rem) => 1rem total.
        let expectedCollapsedBefore = NoteTextParagraphMetrics.bodySpacingRem * viewModel.baseFontSize
        XCTAssertEqual(headingStyle?.paragraphSpacingBefore ?? -1, expectedCollapsedBefore, accuracy: 0.001)
        XCTAssertEqual(bodyStyle?.paragraphSpacing ?? -1, expectedCollapsedBefore, accuracy: 0.001)
    }

    func testNewlineAfterBlockquoteResetsTypingAttributesToParagraph() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("> Quote")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let previous = viewModel.attributedContent
        viewModel.attributedContent.append(AttributedString("\n"))
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.handleContentChange(previous: previous)

        let typingAttributes = viewModel.selection.typingAttributes(in: viewModel.attributedContent)
        XCTAssertNotEqual(typingAttributes.blockKind, .blockquote)
        XCTAssertNil(typingAttributes.backgroundColor)
    }

    private func selectionOffsets(in viewModel: NativeNoteEditorViewModel) -> [Range<Int>] {
        switch viewModel.selection.indices(in: viewModel.attributedContent) {
        case .insertionPoint(let index):
            let offset = viewModel.attributedContent.characters.distance(
                from: viewModel.attributedContent.startIndex,
                to: index
            )
            return [offset..<offset]
        case .ranges(let ranges):
            return ranges.ranges.map { range in
                let lower = viewModel.attributedContent.characters.distance(
                    from: viewModel.attributedContent.startIndex,
                    to: range.lowerBound
                )
                let upper = viewModel.attributedContent.characters.distance(
                    from: viewModel.attributedContent.startIndex,
                    to: range.upperBound
                )
                return lower..<upper
            }
        }
    }

    private func firstLineRange(in text: AttributedString) -> Range<AttributedString.Index> {
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text.characters[cursor].isNewline {
                return text.startIndex..<cursor
            }
            cursor = text.index(afterCharacter: cursor)
        }
        return text.startIndex..<text.endIndex
    }

    private func allLineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
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
