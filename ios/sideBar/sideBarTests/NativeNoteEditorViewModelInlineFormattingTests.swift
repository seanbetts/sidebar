import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorInlineFormattingTests: XCTestCase {
    func testApplyFormattingItalicTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.italic)
        XCTAssertTrue(
            (viewModel.selection.typingAttributes(in: viewModel.attributedContent).inlinePresentationIntent ?? [])
                .contains(.emphasized)
        )

        viewModel.applyFormatting(.italic)
        XCTAssertFalse(
            (viewModel.selection.typingAttributes(in: viewModel.attributedContent).inlinePresentationIntent ?? [])
                .contains(.emphasized)
        )
    }

    func testApplyFormattingInlineCodeTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.inlineCode)
        XCTAssertTrue(
            (viewModel.selection.typingAttributes(in: viewModel.attributedContent).inlinePresentationIntent ?? [])
                .contains(.code)
        )

        viewModel.applyFormatting(.inlineCode)
        XCTAssertFalse(
            (viewModel.selection.typingAttributes(in: viewModel.attributedContent).inlinePresentationIntent ?? [])
                .contains(.code)
        )
    }

    func testApplyFormattingUnderlineTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.underline)
        XCTAssertEqual(
            viewModel.selection.typingAttributes(in: viewModel.attributedContent).underlineStyle,
            .single
        )

        viewModel.applyFormatting(.underline)
        XCTAssertNil(
            viewModel.selection.typingAttributes(in: viewModel.attributedContent).underlineStyle
        )
    }

    func testApplyFormattingDemoteHeadingDefaultsParagraphToHeadingThree() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let lineRange = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: lineRange.lowerBound..<lineRange.upperBound)

        viewModel.applyFormatting(.demoteHeading)

        let updatedLine = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedLine), .heading3)
    }

    func testApplyFormattingBoldStylesSelectedRangeImmediately() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let lineRange = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: lineRange.lowerBound..<lineRange.upperBound)

        viewModel.applyFormatting(.bold)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let hasBoldRun = viewModel.attributedContent[lineRange].runs.contains { run in
            #if os(iOS)
            guard let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif os(macOS)
            guard let font = run[AttributeScopes.AppKitAttributes.FontAttribute.self] else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        }
        XCTAssertTrue(hasBoldRun)
    }

    func testApplyFormattingBulletListPrefixesCurrentLine() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("item")
        let lineRange = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: lineRange.lowerBound..<lineRange.upperBound)

        viewModel.applyFormatting(.bulletList)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(String(viewModel.attributedContent.characters).hasPrefix("• "))
        let updatedLine = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedLine), .bulletList)
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
