import SwiftUI
import XCTest
#if os(macOS)
import AppKit
#endif
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
            guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        }
        XCTAssertTrue(hasBoldRun)
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

#if os(macOS)
    private func bridgedPlatformFont(from run: AttributedString.Runs.Run) -> AnyObject? {
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(run.attributes)
        let bridged = NSAttributedString(sample)
        return bridged.attribute(NSAttributedString.Key.font, at: 0, effectiveRange: nil) as AnyObject?
    }
#endif
}
