import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeMarkdownListContinuationTests: XCTestCase {
    func testEnterInBulletListContinuesListFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("- Item")
        await waitForPrefixVisibility(on: viewModel)

        pressReturn(in: viewModel)

        let newlineIndex = viewModel.attributedContent.index(beforeCharacter: viewModel.attributedContent.endIndex)
        let newlineRange = newlineIndex..<viewModel.attributedContent.endIndex
        XCTAssertEqual(viewModel.attributedContent[newlineRange].blockKind, .bulletList)
        XCTAssertEqual(viewModel.attributedContent[newlineRange].listDepth, 1)

        let previous = viewModel.attributedContent
        insertText("Next", in: viewModel)
        viewModel.handleContentChange(previous: previous)

        XCTAssertEqual(viewModel.currentMarkdown(), "- Item\n- Next")
    }

    func testEnterInOrderedListContinuesAndAdvancesOrdinal() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("1. One")
        await waitForPrefixVisibility(on: viewModel)

        pressReturn(in: viewModel)

        let newlineIndex = viewModel.attributedContent.index(beforeCharacter: viewModel.attributedContent.endIndex)
        let newlineRange = newlineIndex..<viewModel.attributedContent.endIndex
        XCTAssertEqual(viewModel.attributedContent[newlineRange].blockKind, .orderedList)

        let previous = viewModel.attributedContent
        insertText("Two", in: viewModel)
        viewModel.handleContentChange(previous: previous)

        XCTAssertEqual(viewModel.currentMarkdown(), "1. One\n2. Two")
    }

    func testEnterAfterCheckedTaskStartsUncheckedTask() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("- [x] Done")
        await waitForPrefixVisibility(on: viewModel)

        pressReturn(in: viewModel)

        let previous = viewModel.attributedContent
        insertText("Next", in: viewModel)
        viewModel.handleContentChange(previous: previous)

        XCTAssertEqual(viewModel.currentMarkdown(), "- [x] ~~Done~~\n- [ ] Next")
    }

    func testEnterOnEmptyBulletListItemExitsList() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("- Item")
        await waitForPrefixVisibility(on: viewModel)

        pressReturn(in: viewModel)
        pressReturn(in: viewModel)

        let markdown = viewModel.currentMarkdown()
        XCTAssertTrue(markdown.hasPrefix("- Item"))
        XCTAssertFalse(markdown.contains("\n- "))
    }

    func testEnterOnEmptyOrderedListItemExitsList() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("1. One")
        await waitForPrefixVisibility(on: viewModel)

        pressReturn(in: viewModel)
        pressReturn(in: viewModel)

        let markdown = viewModel.currentMarkdown()
        XCTAssertTrue(markdown.hasPrefix("1. One"))
        XCTAssertFalse(markdown.contains("\n2. "))
    }

    func testEnterOnEmptyTaskListItemExitsList() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("- [ ] Todo")
        await waitForPrefixVisibility(on: viewModel)

        pressReturn(in: viewModel)
        pressReturn(in: viewModel)

        let markdown = viewModel.currentMarkdown()
        XCTAssertTrue(markdown.hasPrefix("- [ ] Todo"))
        XCTAssertEqual(markdown.components(separatedBy: "- [ ]").count - 1, 1)
    }

    private func waitForPrefixVisibility(on viewModel: NativeNoteEditorViewModel) async {
        for _ in 0..<20 where viewModel.isUpdatingPrefixVisibility {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func pressReturn(in viewModel: NativeNoteEditorViewModel) {
        let previous = viewModel.attributedContent
        guard let insertion = insertionIndex(in: viewModel.selection, text: viewModel.attributedContent) else {
            XCTFail("Expected insertion selection")
            return
        }
        viewModel.attributedContent.insert(AttributedString("\n"), at: insertion)
        let cursor = viewModel.attributedContent.index(insertion, offsetByCharacters: 1)
        viewModel.selection = AttributedTextSelection(range: cursor..<cursor)
        viewModel.handleContentChange(previous: previous)
    }

    private func insertText(_ string: String, in viewModel: NativeNoteEditorViewModel) {
        guard let insertion = insertionIndex(in: viewModel.selection, text: viewModel.attributedContent) else {
            XCTFail("Expected insertion selection")
            return
        }

        var insert = AttributedString(string)
        let range = insert.startIndex..<insert.endIndex
        var attrs = viewModel.selection.typingAttributes(in: viewModel.attributedContent)
        if attrs.blockKind == nil, insertion > viewModel.attributedContent.startIndex {
            let previousIndex = viewModel.attributedContent.index(beforeCharacter: insertion)
            let previousRange = previousIndex..<insertion
            attrs.blockKind = viewModel.attributedContent[previousRange].blockKind
            attrs.listDepth = viewModel.attributedContent[previousRange].listDepth
            attrs.paragraphStyle = viewModel.attributedContent[previousRange].paragraphStyle
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
                viewModel.attributedContent[previousRange][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
            attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] =
                viewModel.attributedContent[previousRange][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self]
        }
        insert[range].mergeAttributes(attrs)
        viewModel.attributedContent.insert(insert, at: insertion)
        let end = viewModel.attributedContent.index(insertion, offsetByCharacters: string.count)
        viewModel.selection = AttributedTextSelection(range: end..<end)
    }

    private func insertionIndex(
        in selection: AttributedTextSelection,
        text: AttributedString
    ) -> AttributedString.Index? {
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            return index
        case .ranges(let ranges):
            for range in ranges.ranges where range.isEmpty {
                return range.lowerBound
            }
            return nil
        }
    }
}
