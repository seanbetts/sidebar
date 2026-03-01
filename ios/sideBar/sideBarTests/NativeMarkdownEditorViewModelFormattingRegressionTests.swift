import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeMarkdownEditorRegressionTests: XCTestCase {
    func testApplyFormattingPromoteAndDemoteHeadingAdjustLevel() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadText("hello")
        var lineRange = firstLine(in: viewModel.attributedContent)
        viewModel.attributedContent[lineRange].blockKind = .heading3
        viewModel.selection = AttributedTextSelection(range: lineRange.lowerBound..<lineRange.upperBound)

        viewModel.applyFormatting(.promoteHeading)
        lineRange = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: lineRange), .heading2)

        viewModel.selection = AttributedTextSelection(range: lineRange.lowerBound..<lineRange.upperBound)
        viewModel.applyFormatting(.demoteHeading)
        lineRange = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: lineRange), .heading3)
    }

    func testApplyFormattingPromoteHeadingDefaultsParagraphToHeadingTwo() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadText("hello")
        let lineRange = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: lineRange.lowerBound..<lineRange.upperBound)

        viewModel.applyFormatting(.promoteHeading)

        let updatedLine = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedLine), .heading2)
    }

    func testHandleContentChangeRemovesUnderlineFromNonLinksOnly() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadText("plain\nlinked")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let firstLineRange = firstLine(in: viewModel.attributedContent)
        var secondLineRange = lineRanges(in: viewModel.attributedContent)[1]

        viewModel.attributedContent[firstLineRange].underlineStyle = .single
        viewModel.attributedContent[secondLineRange].underlineStyle = .single
        viewModel.attributedContent[secondLineRange].link = URL(string: "https://example.com")!

        let previous = viewModel.attributedContent
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.handleContentChange(previous: previous)

        let updatedFirstLine = firstLine(in: viewModel.attributedContent)
        secondLineRange = lineRanges(in: viewModel.attributedContent)[1]
        XCTAssertNil(viewModel.attributedContent[updatedFirstLine].underlineStyle)
        XCTAssertEqual(viewModel.attributedContent[secondLineRange].underlineStyle, .single)
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
