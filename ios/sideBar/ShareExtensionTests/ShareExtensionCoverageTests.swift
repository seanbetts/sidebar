import Foundation
import XCTest
@testable import ShareExtension
import sideBarShared

final class ShareExtensionCoverageTests: XCTestCase {
    func testErrorMessageUsesCatalogForNotAuthenticated() {
        let message = ShareExtensionMessageMapper.errorMessage(for: ShareExtensionError.notAuthenticated)

        XCTAssertEqual(
            message,
            ExtensionUserMessageCatalog.message(for: .notAuthenticated)
        )
    }

    func testErrorMessageIncludesSanitizedUploadFailureDetail() {
        let message = ShareExtensionMessageMapper.errorMessage(
            for: ShareExtensionError.uploadFailed("upload failed: backend temporarily unavailable")
        )

        XCTAssertEqual(
            message,
            "Upload failed. Please try again. backend temporarily unavailable"
        )
    }

    func testQueueMessageReflectsQueueResult() {
        let queued = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: Date(),
            url: "https://example.com"
        )

        XCTAssertTrue(ShareExtensionMessageMapper.queueSucceeded(for: queued))
        XCTAssertEqual(
            ShareExtensionMessageMapper.queueResultMessage(for: queued),
            ExtensionUserMessageCatalog.message(for: .savedForLater)
        )

        XCTAssertFalse(ShareExtensionMessageMapper.queueSucceeded(for: nil))
        XCTAssertEqual(
            ShareExtensionMessageMapper.queueResultMessage(for: nil),
            ExtensionUserMessageCatalog.message(for: .queueFailed)
        )
    }

    func testExtractFirstURLFindsURLInPlainText() {
        let controller = ShareViewController()
        let text = "Please review https://example.com/docs?tab=1 before launch."

        let url = controller.extractFirstURL(from: text)

        XCTAssertEqual(url?.absoluteString, "https://example.com/docs?tab=1")
    }

    func testMimeTypeForFilenameUsesKnownAndFallbackMappings() {
        let controller = ShareViewController()

        XCTAssertEqual(controller.mimeTypeForFilename("presentation.pptx"), "application/vnd.openxmlformats-officedocument.presentationml.presentation")
        XCTAssertEqual(controller.mimeTypeForFilename("unknown.custom"), "application/octet-stream")
    }
}
