import XCTest
@testable import sideBar

final class MarkdownTypographyTests: XCTestCase {
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
