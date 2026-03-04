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
            guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        }
        XCTAssertTrue(hasBoldRun)
    }

    func testBoldActiveFallsBackToFontTraitsWhenIntentMissing() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.setEnabledFormattingCapabilities([.bold])
        viewModel.setPlainTextRuntimeModeEnabled(true)
        viewModel.loadText("hello")
        let lineRange = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: lineRange.lowerBound..<lineRange.upperBound)
        let platformBold = viewModel.platformFontApplyingTraits(
            viewModel.platformBaseFont(for: .paragraph),
            bold: true,
            italic: false
        )
        viewModel.setFont(
            .system(size: viewModel.baseFontSize, weight: .bold),
            platformFont: platformBold,
            in: &viewModel.attributedContent,
            range: lineRange
        )
        viewModel.attributedContent[lineRange].inlinePresentationIntent = []

        XCTAssertTrue(viewModel.isBoldActive())
    }

    func testApplyFormattingBoldTogglesOffTraitOnlyBoldSelection() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.setEnabledFormattingCapabilities([.bold])
        viewModel.setPlainTextRuntimeModeEnabled(true)
        viewModel.loadText("hello")
        let lineRange = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: lineRange.lowerBound..<lineRange.upperBound)
        let platformBold = viewModel.platformFontApplyingTraits(
            viewModel.platformBaseFont(for: .paragraph),
            bold: true,
            italic: false
        )
        viewModel.setFont(
            .system(size: viewModel.baseFontSize, weight: .bold),
            platformFont: platformBold,
            in: &viewModel.attributedContent,
            range: lineRange
        )
        viewModel.attributedContent[lineRange].inlinePresentationIntent = []
        let refreshedSelectionRange = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(
            range: refreshedSelectionRange.lowerBound..<refreshedSelectionRange.upperBound
        )

        XCTAssertTrue(viewModel.isBoldActive())
        XCTAssertTrue(hasBoldTrait(in: viewModel.attributedContent, range: lineRange))

        viewModel.applyFormatting(.bold)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let updatedRange = firstLine(in: viewModel.attributedContent)
        let remainingIntents = viewModel.attributedContent[updatedRange].runs.compactMap { run in
            run.inlinePresentationIntent
        }
        let hasRemainingBoldIntent = remainingIntents.contains { intents in
            intents.contains(.stronglyEmphasized)
        }
        let hasRemainingBoldTrait = hasBoldTrait(in: viewModel.attributedContent, range: updatedRange)
        XCTAssertFalse(
            viewModel.isBoldActive(),
            "Expected custom toolbar state to report inactive after toggling trait-only bold off. " +
                "remainingBoldIntent=\(hasRemainingBoldIntent) remainingBoldTrait=\(hasRemainingBoldTrait)"
        )
        XCTAssertFalse(
            hasRemainingBoldTrait,
            "Expected font trait to be removed after toggling trait-only bold off."
        )
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

    private func hasBoldTrait(
        in text: AttributedString,
        range: Range<AttributedString.Index>
    ) -> Bool {
        text[range].runs.contains { run in
            #if os(iOS)
            guard let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif os(macOS)
            guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        }
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
