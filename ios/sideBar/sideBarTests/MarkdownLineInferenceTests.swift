import XCTest
@testable import sideBar

@available(iOS 26.0, macOS 26.0, *)
final class MarkdownLineInferenceTests: XCTestCase {
    func testInferListBlockKindSupportsRenderedAndRawPrefixes() {
        XCTAssertEqual(MarkdownLineInference.inferListBlockKind(from: "• Bullet"), .bulletList)
        XCTAssertEqual(MarkdownLineInference.inferListBlockKind(from: "☑ Done"), .taskChecked)
        XCTAssertEqual(MarkdownLineInference.inferListBlockKind(from: "☐ Todo"), .taskUnchecked)
        XCTAssertEqual(MarkdownLineInference.inferListBlockKind(from: "- [x] Done"), .taskChecked)
        XCTAssertEqual(MarkdownLineInference.inferListBlockKind(from: "1. Ordered"), .orderedList)
    }

    func testInferBlockKindSupportsThematicBreakHeadingAndBlockquote() {
        XCTAssertEqual(MarkdownLineInference.inferBlockKind(from: "---"), .horizontalRule)
        XCTAssertEqual(MarkdownLineInference.inferBlockKind(from: "## Heading"), .heading2)
        XCTAssertEqual(MarkdownLineInference.inferBlockKind(from: "> Quote"), .blockquote)
        XCTAssertEqual(MarkdownLineInference.inferBlockKind(from: "│ Quote"), .blockquote)
    }

    func testShortcutInferenceStaysAlignedWithSharedInference() {
        let samples = [
            "• Item",
            "☑ Done",
            "☐ Todo",
            "- [x] Done",
            "1. Ordered"
        ]

        for sample in samples {
            XCTAssertEqual(
                MarkdownShortcutProcessor.inferredListBlockKind(from: sample),
                MarkdownLineInference.inferListBlockKind(from: sample),
                "Mismatch for sample: \(sample)"
            )
        }
    }
}
