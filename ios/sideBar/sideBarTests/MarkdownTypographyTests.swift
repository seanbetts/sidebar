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
}
