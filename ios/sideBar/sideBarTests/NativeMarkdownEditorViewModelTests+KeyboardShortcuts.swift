import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModelTests {
    func testHandleListDepthKeyboardShortcutIndentsListParagraphWithinMixedSelection() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.attributedContent = AttributedString("List line\nPlain line")
        var ranges = keyboardLineRanges(in: viewModel.attributedContent)
        XCTAssertEqual(ranges.count, 2)

        viewModel.attributedContent[ranges[0]].blockKind = .bulletList
        viewModel.attributedContent[ranges[0]].listDepth = 1
        ranges = keyboardLineRanges(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: ranges[0].lowerBound..<ranges[1].upperBound)

        let handled = viewModel.handleListDepthKeyboardShortcut(outdent: false)

        XCTAssertTrue(handled)
        let updatedRanges = keyboardLineRanges(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedRanges[0]), .bulletList)
        XCTAssertEqual(viewModel.attributedContent[updatedRanges[0]].listDepth, 2)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedRanges[1]) ?? .paragraph, .paragraph)
        XCTAssertNil(viewModel.attributedContent[updatedRanges[1]].listDepth)
    }

    func testHandleListDepthKeyboardShortcutReturnsFalseWhenReadOnlyListSelected() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown("List item")
        var line = keyboardFirstLine(in: viewModel.attributedContent)
        viewModel.attributedContent[line].blockKind = .bulletList
        viewModel.attributedContent[line].listDepth = 1
        line = keyboardFirstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: line.lowerBound..<line.upperBound)
        viewModel.isReadOnly = true

        let handled = viewModel.handleListDepthKeyboardShortcut(outdent: false)

        XCTAssertFalse(handled)
        line = keyboardFirstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: line), .bulletList)
        XCTAssertEqual(viewModel.attributedContent[line].listDepth, 1)
    }
}

private func keyboardFirstLine(in text: AttributedString) -> Range<AttributedString.Index> {
    var cursor = text.startIndex
    while cursor < text.endIndex {
        if text.characters[cursor].isNewline {
            return text.startIndex..<cursor
        }
        cursor = text.index(afterCharacter: cursor)
    }
    return text.startIndex..<text.endIndex
}

private func keyboardLineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
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
