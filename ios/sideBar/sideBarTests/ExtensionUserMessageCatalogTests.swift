import XCTest
import sideBarShared

final class ExtensionUserMessageCatalogTests: XCTestCase {
    func testUploadFailureMessageAvoidsDoublePrefix() {
        let message = ExtensionUserMessageCatalog.uploadFailureMessage(detail: "Upload failed: HTTP 413")
        XCTAssertEqual(message, "Upload failed. Please try again. HTTP 413")
    }

    func testSanitizedDetailDropsSystemFallback() {
        let detail = ExtensionUserMessageCatalog.sanitizedDetail(
            "The operation couldn’t be completed. (NSURLErrorDomain error -1009.)"
        )
        XCTAssertNil(detail)
    }

    func testMissingUrlMessageIsUserFriendly() {
        let message = ExtensionUserMessageCatalog.message(for: .missingURL)
        XCTAssertEqual(message, "No active tab URL found.")
    }
}
