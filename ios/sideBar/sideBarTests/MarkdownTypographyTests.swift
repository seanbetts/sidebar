import XCTest
@testable import sideBar

final class MarkdownTypographyTests: XCTestCase {
    func testDefaultHeadingSizesMatchLegacyScale() {
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 1), 32, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 2), 24, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 3), 20, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 4), 18, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 5), 17, accuracy: 0.001)
        XCTAssertEqual(MarkdownHeadingMetrics.fontSize(for: 6), 16, accuracy: 0.001)
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
}
