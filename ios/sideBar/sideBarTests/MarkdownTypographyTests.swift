import XCTest
@testable import sideBar
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class MarkdownTypographyTests: XCTestCase {
    func testLegacyHeadingScaleWhenBaseIs16() {
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 1, baseFontSize: 16), 32, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 2, baseFontSize: 16), 24, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 3, baseFontSize: 16), 20, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 4, baseFontSize: 16), 18, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 5, baseFontSize: 16), 17, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 6, baseFontSize: 16), 16, accuracy: 0.001)
    }

    func testDefaultHeadingSizeUsesSharedBodyBase() {
        XCTAssertEqual(
            MarkdownHeadingMetrics.fontSize(for: 2),
            MarkdownTypography.defaultBodyFontSize * 1.5,
            accuracy: 0.001
        )
    }

    func testHeadingSizesScaleWithCustomBaseFontSize() {
        XCTAssertEqual(
            MarkdownHeadingMetrics.fontSize(for: 2, baseFontSize: 20),
            30,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MarkdownHeadingMetrics.fontSize(for: 4, baseFontSize: 20),
            22.5,
            accuracy: 0.001
        )
    }

    func testInlineCodeSizeScalesFromBodyFontSize() {
        XCTAssertEqual(
            MarkdownTypography.inlineCodeFontSize(baseFontSize: 16),
            14,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MarkdownTypography.inlineCodeFontSize(baseFontSize: 20),
            17.5,
            accuracy: 0.001
        )
    }

    func testHeadingParagraphStyleMatchesMarkdownGuideSpacing() {
        let baseFont: CGFloat = 16
        let h1Style = MarkdownHeadingMetrics.paragraphStyle(level: 1, baseFontSize: baseFont)
        let h1FontSize = MarkdownHeadingMetrics.fontSize(for: 1, baseFontSize: baseFont)
        let h1LineHeight = h1FontSize * 1.3
        let h1ExpectedSpacing = max(0, h1LineHeight - naturalLineHeight(fontSize: h1FontSize, weight: .bold))
        XCTAssertEqual(h1Style.paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(h1Style.paragraphSpacing, 4.8, accuracy: 0.001)
        XCTAssertEqual(h1Style.lineSpacing, h1ExpectedSpacing, accuracy: 0.001)

        let h2Style = MarkdownHeadingMetrics.paragraphStyle(level: 2, baseFontSize: baseFont)
        let h2FontSize = MarkdownHeadingMetrics.fontSize(for: 2, baseFontSize: baseFont)
        let h2LineHeight = h2FontSize * 1.3
        let h2ExpectedSpacing = max(
            0,
            h2LineHeight - naturalLineHeight(fontSize: h2FontSize, weight: .semibold)
        )
        XCTAssertEqual(h2Style.paragraphSpacingBefore, 16, accuracy: 0.001)
        XCTAssertEqual(h2Style.paragraphSpacing, 4.8, accuracy: 0.001)
        XCTAssertEqual(h2Style.lineSpacing, h2ExpectedSpacing, accuracy: 0.001)
    }

    func testHeadingWeightMatchesMarkdownGuide() {
        XCTAssertTrue(MarkdownHeadingMetrics.isBold(level: 1))
        XCTAssertFalse(MarkdownHeadingMetrics.isBold(level: 2))
        XCTAssertFalse(MarkdownHeadingMetrics.isBold(level: 6))
    }

    func testBodyParagraphStyleMatchesMarkdownGuideLineHeightAndSpacing() {
        let style = MarkdownParagraphMetrics.bodyParagraphStyle(baseFontSize: 16)
        let expectedLineSpacing = max(
            0,
            (16 * MarkdownParagraphMetrics.bodyLineHeightMultiple) - naturalLineHeight(fontSize: 16, weight: .regular)
        )
        XCTAssertEqual(style.paragraphSpacingBefore, 8, accuracy: 0.001)
        XCTAssertEqual(style.paragraphSpacing, 8, accuracy: 0.001)
        XCTAssertEqual(style.lineSpacing, expectedLineSpacing, accuracy: 0.001)
    }

    func testListParagraphStyleMatchesMarkdownGuideLineHeightAndSpacing() {
        let style = MarkdownParagraphMetrics.listParagraphStyle(baseFontSize: 16)
        let expectedLineSpacing = max(
            0,
            (16 * MarkdownParagraphMetrics.listLineHeightMultiple) - naturalLineHeight(fontSize: 16, weight: .regular)
        )
        XCTAssertEqual(style.paragraphSpacingBefore, 8, accuracy: 0.001)
        XCTAssertEqual(style.paragraphSpacing, 8, accuracy: 0.001)
        XCTAssertEqual(style.lineSpacing, expectedLineSpacing, accuracy: 0.001)
    }

    func testNestedListParagraphStyleRemovesExtraTopBottomSpacing() {
        let style = MarkdownParagraphMetrics.listParagraphStyle(baseFontSize: 16, listDepth: 2)
        let expectedLineSpacing = max(
            0,
            (16 * MarkdownParagraphMetrics.listLineHeightMultiple) - naturalLineHeight(fontSize: 16, weight: .regular)
        )
        XCTAssertEqual(style.paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(style.paragraphSpacing, 0, accuracy: 0.001)
        XCTAssertEqual(style.lineSpacing, expectedLineSpacing, accuracy: 0.001)
    }

    func testBlockquoteParagraphStyleMatchesMarkdownGuideSpacingAndLineHeight() {
        let style = MarkdownParagraphMetrics.blockquoteParagraphStyle(baseFontSize: 16, headIndent: 16)
        let expectedLineSpacing = max(
            0,
            (16 * MarkdownParagraphMetrics.bodyLineHeightMultiple) - naturalLineHeight(fontSize: 16, weight: .regular)
        )
        XCTAssertEqual(style.paragraphSpacingBefore, 16, accuracy: 0.001)
        XCTAssertEqual(style.paragraphSpacing, 16, accuracy: 0.001)
        XCTAssertEqual(style.lineSpacing, expectedLineSpacing, accuracy: 0.001)
        XCTAssertEqual(style.headIndent, 16, accuracy: 0.001)
    }

    func testFootnoteSizeScalesFromBodyFontSize() {
        let baseBody = MarkdownTypography.defaultBodyFontSize(for: .system)
        let baseFootnote = MarkdownTypography.footnoteFontSize(baseFontSize: baseBody)
        let expectedRatio = AppTextSizeOption.large.scaleMultiplier / AppTextSizeOption.small.scaleMultiplier

        XCTAssertEqual(
            MarkdownTypography.footnoteFontSize(baseFontSize: baseBody * AppTextSizeOption.small.scaleMultiplier),
            baseFootnote * AppTextSizeOption.small.scaleMultiplier,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MarkdownTypography.footnoteFontSize(baseFontSize: baseBody * AppTextSizeOption.large.scaleMultiplier)
                / MarkdownTypography.footnoteFontSize(baseFontSize: baseBody * AppTextSizeOption.small.scaleMultiplier),
            expectedRatio,
            accuracy: 0.001
        )
    }
}

private enum FontWeightAlias {
    case regular
    case semibold
    case bold
}

private func naturalLineHeight(fontSize: CGFloat, weight: FontWeightAlias) -> CGFloat {
#if canImport(UIKit)
    let uiWeight: UIFont.Weight
    switch weight {
    case .regular:
        uiWeight = .regular
    case .semibold:
        uiWeight = .semibold
    case .bold:
        uiWeight = .bold
    }
    return UIFont.systemFont(ofSize: fontSize, weight: uiWeight).lineHeight
#elseif canImport(AppKit)
    let appKitWeight: NSFont.Weight
    switch weight {
    case .regular:
        appKitWeight = .regular
    case .semibold:
        appKitWeight = .semibold
    case .bold:
        appKitWeight = .bold
    }
    return NSFont.systemFont(ofSize: fontSize, weight: appKitWeight).lineHeight
#else
    return fontSize
#endif
}
