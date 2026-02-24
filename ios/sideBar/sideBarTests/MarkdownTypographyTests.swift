import XCTest
@testable import sideBar

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
        let h1LineHeight = MarkdownHeadingMetrics.fontSize(for: 1, baseFontSize: baseFont) * 1.3
        XCTAssertEqual(h1Style.paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(h1Style.paragraphSpacing, 4.8, accuracy: 0.001)
        XCTAssertEqual(h1Style.minimumLineHeight, h1LineHeight, accuracy: 0.001)
        XCTAssertEqual(h1Style.maximumLineHeight, h1LineHeight, accuracy: 0.001)

        let h2Style = MarkdownHeadingMetrics.paragraphStyle(level: 2, baseFontSize: baseFont)
        let h2LineHeight = MarkdownHeadingMetrics.fontSize(for: 2, baseFontSize: baseFont) * 1.3
        XCTAssertEqual(h2Style.paragraphSpacingBefore, 16, accuracy: 0.001)
        XCTAssertEqual(h2Style.paragraphSpacing, 4.8, accuracy: 0.001)
        XCTAssertEqual(h2Style.minimumLineHeight, h2LineHeight, accuracy: 0.001)
        XCTAssertEqual(h2Style.maximumLineHeight, h2LineHeight, accuracy: 0.001)
    }

    func testHeadingWeightMatchesMarkdownGuide() {
        XCTAssertTrue(MarkdownHeadingMetrics.isBold(level: 1))
        XCTAssertFalse(MarkdownHeadingMetrics.isBold(level: 2))
        XCTAssertFalse(MarkdownHeadingMetrics.isBold(level: 6))
    }

    func testBodyParagraphStyleMatchesMarkdownGuideLineHeightAndSpacing() {
        let style = MarkdownParagraphMetrics.bodyParagraphStyle(baseFontSize: 16)
        XCTAssertEqual(style.paragraphSpacingBefore, 8, accuracy: 0.001)
        XCTAssertEqual(style.paragraphSpacing, 8, accuracy: 0.001)
        XCTAssertEqual(style.minimumLineHeight, 27.2, accuracy: 0.001)
        XCTAssertEqual(style.maximumLineHeight, 27.2, accuracy: 0.001)
    }

    func testListParagraphStyleMatchesMarkdownGuideLineHeightAndSpacing() {
        let style = MarkdownParagraphMetrics.listParagraphStyle(baseFontSize: 16)
        XCTAssertEqual(style.paragraphSpacingBefore, 8, accuracy: 0.001)
        XCTAssertEqual(style.paragraphSpacing, 8, accuracy: 0.001)
        XCTAssertEqual(style.minimumLineHeight, 22.4, accuracy: 0.001)
        XCTAssertEqual(style.maximumLineHeight, 22.4, accuracy: 0.001)
    }

    func testNestedListParagraphStyleRemovesExtraTopBottomSpacing() {
        let style = MarkdownParagraphMetrics.listParagraphStyle(baseFontSize: 16, listDepth: 2)
        XCTAssertEqual(style.paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(style.paragraphSpacing, 0, accuracy: 0.001)
        XCTAssertEqual(style.minimumLineHeight, 22.4, accuracy: 0.001)
        XCTAssertEqual(style.maximumLineHeight, 22.4, accuracy: 0.001)
    }

    func testBlockquoteParagraphStyleMatchesMarkdownGuideSpacingAndLineHeight() {
        let style = MarkdownParagraphMetrics.blockquoteParagraphStyle(baseFontSize: 16, headIndent: 16)
        XCTAssertEqual(style.paragraphSpacingBefore, 16, accuracy: 0.001)
        XCTAssertEqual(style.paragraphSpacing, 16, accuracy: 0.001)
        XCTAssertEqual(style.minimumLineHeight, 27.2, accuracy: 0.001)
        XCTAssertEqual(style.maximumLineHeight, 27.2, accuracy: 0.001)
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
