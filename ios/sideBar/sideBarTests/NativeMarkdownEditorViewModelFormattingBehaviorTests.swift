import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeMarkdownFormattingBehaviorTests: XCTestCase {
    func testPromoteHeadingKeepsSelectedRange() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("hello world")

        let start = viewModel.attributedContent.startIndex
        let end = viewModel.attributedContent.index(start, offsetByCharacters: 5)
        viewModel.selection = AttributedTextSelection(range: start..<end)

        let before = selectionOffsets(in: viewModel)
        viewModel.applyFormatting(.promoteHeading)
        let after = selectionOffsets(in: viewModel)

        XCTAssertEqual(before, after)
    }

    func testCanAdjustListDepthWhenParagraphIsListBlock() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("Item")
        var line = firstLineRange(in: viewModel.attributedContent)
        viewModel.attributedContent[line].blockKind = .bulletList
        viewModel.attributedContent[line].listDepth = 1
        line = firstLineRange(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: line.lowerBound..<line.upperBound)

        XCTAssertTrue(viewModel.canAdjustListDepth())
    }

    func testBlockquoteDisplaysReadMarkerAndExportsCleanMarkdown() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.usesInjectedListMarkers = false
        viewModel.loadMarkdown("> Quoted")
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(String(viewModel.attributedContent.characters).hasPrefix("│ "))
        XCTAssertEqual(viewModel.currentMarkdown(), "> Quoted")
    }

    func testHorizontalRuleInsertionProducesMarkdownRule() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("alpha")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.horizontalRule)

        XCTAssertEqual(viewModel.currentMarkdown(), "alpha\n\n---")
    }

    func testHeadingParagraphStyleRetainsVerticalSpacing() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("## Heading\nBody")

        let firstLine = firstLineRange(in: viewModel.attributedContent)
        let style = viewModel.attributedContent[firstLine].paragraphStyle
        XCTAssertNotNil(style)
        XCTAssertGreaterThan(style?.paragraphSpacingBefore ?? 0, 0)
        XCTAssertGreaterThan(style?.paragraphSpacing ?? 0, 0)
    }

    private func selectionOffsets(in viewModel: NativeMarkdownEditorViewModel) -> [Range<Int>] {
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
}
