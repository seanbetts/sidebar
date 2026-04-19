import XCTest
@testable import sideBar

final class ChatStreamingDebugTraceTests: XCTestCase {
    func testIsEnabledRequiresExplicitOne() {
        XCTAssertTrue(
            ChatStreamingDebugTrace.isEnabled(
                environment: [ChatStreamingDebugTrace.environmentVariable: "1"]
            )
        )
        XCTAssertFalse(
            ChatStreamingDebugTrace.isEnabled(
                environment: [ChatStreamingDebugTrace.environmentVariable: "0"]
            )
        )
        XCTAssertFalse(ChatStreamingDebugTrace.isEnabled(environment: [:]))
    }

    func testVisibleWhitespaceEscapesControlCharacters() {
        XCTAssertEqual(
            ChatStreamingDebugTrace.visibleWhitespacePreview("Line 1\n\tLine 2\r\nLine 3"),
            #"Line 1\n\tLine 2\r\nLine 3"#
        )
    }

    func testVisibleWhitespacePreviewTruncatesLongContent() {
        XCTAssertEqual(
            ChatStreamingDebugTrace.visibleWhitespacePreview("abcdef", limit: 4),
            "abcd..."
        )
    }
}
