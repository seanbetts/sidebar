import XCTest
@testable import sideBarShared

final class LogRedactionTests: XCTestCase {
    func testRedactedURLKeepsSchemeHostAndPortOnly() {
        let url = URL(string: "https://example.com:8443/private/path?token=secret#fragment")

        XCTAssertEqual(LogRedaction.redactedURLString(url), "https://example.com:8443")
    }

    func testRedactedURLHandlesCustomSchemeWithoutPath() {
        let url = URL(string: "sidebar://notes/note-123?token=secret")

        XCTAssertEqual(LogRedaction.redactedURLString(url), "sidebar://notes")
    }

    func testRedactedURLStringMarksInvalidValues() {
        XCTAssertEqual(LogRedaction.redactedURLString("not a url"), "invalid-url")
    }

    func testRedactedURLRejectsEncodedQuestionMarkInHost() {
        let url = URL(string: "https://example.com%3Ftoken=secret/path")

        XCTAssertEqual(LogRedaction.redactedURLString(url), "invalid-url")
    }

    func testRedactedURLRejectsEncodedSlashInHost() {
        let url = URL(string: "https://example.com%2Fprivate/path")

        XCTAssertEqual(LogRedaction.redactedURLString(url), "invalid-url")
    }

    func testPayloadSummaryDoesNotIncludeRawURL() {
        let summary = LogRedaction.safariPayloadSummary(
            action: "save_url",
            urlString: "https://example.com/private?q=1"
        )

        XCTAssertEqual(summary, "action=save_url has_url=true")
        XCTAssertFalse(summary.contains("example.com/private"))
    }
}
