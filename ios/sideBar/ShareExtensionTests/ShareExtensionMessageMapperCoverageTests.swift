import Foundation
import XCTest
@testable import ShareExtension
import sideBarShared

final class ShareExtensionMessageMapperCoverageTests: XCTestCase {
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

    func testErrorMessageMapsUnauthorizedApiStatusToNotAuthenticated() {
        let message = ShareExtensionMessageMapper.errorMessage(for: APIClientError.requestFailed(401))

        XCTAssertEqual(
            message,
            ExtensionUserMessageCatalog.message(for: .notAuthenticated)
        )
    }

    func testErrorMessageMapsForbiddenApiStatusToNotAuthenticated() {
        let message = ShareExtensionMessageMapper.errorMessage(for: APIClientError.requestFailed(403))

        XCTAssertEqual(
            message,
            ExtensionUserMessageCatalog.message(for: .notAuthenticated)
        )
    }

    func testErrorMessageMapsRateLimitAndServerStatusesToUploadFailed() {
        let rateLimitMessage = ShareExtensionMessageMapper.errorMessage(for: APIClientError.requestFailed(429))
        let serverMessage = ShareExtensionMessageMapper.errorMessage(for: APIClientError.requestFailed(500))

        XCTAssertEqual(rateLimitMessage, ExtensionUserMessageCatalog.message(for: .uploadFailed))
        XCTAssertEqual(serverMessage, ExtensionUserMessageCatalog.message(for: .uploadFailed))
    }

    func testErrorMessageMapsUnauthorizedApiDetailToNotAuthenticated() {
        let message = ShareExtensionMessageMapper.errorMessage(
            for: APIClientError.apiError("JWT expired or unauthorized")
        )

        XCTAssertEqual(
            message,
            ExtensionUserMessageCatalog.message(for: .notAuthenticated)
        )
    }

    func testErrorMessageFallsBackToUnknownFailureForUnclassifiedError() {
        let message = ShareExtensionMessageMapper.errorMessage(
            for: NSError(domain: "ShareExtensionCoverageTests", code: -99)
        )

        XCTAssertEqual(
            message,
            ExtensionUserMessageCatalog.message(for: .unknownFailure)
        )
    }

    func testErrorMessageMapsTimeoutToNetworkMessage() {
        let message = ShareExtensionMessageMapper.errorMessage(for: URLError(.timedOut))

        XCTAssertEqual(
            message,
            ExtensionUserMessageCatalog.message(for: .networkError)
        )
    }

    func testErrorMessageMapsOfflineAppErrorToNetworkMessage() {
        let message = ShareExtensionMessageMapper.errorMessage(
            for: AppError(
                category: .offline,
                operation: "share_extension.upload_file",
                requestKind: .multipartUpload,
                retryability: .allowsOfflineHandoff,
                recommendedSurface: .offlineBanner
            )
        )

        XCTAssertEqual(
            message,
            ExtensionUserMessageCatalog.message(for: .networkError)
        )
    }

    func testErrorMessageMapsAuthenticationAppErrorToNotAuthenticated() {
        let message = ShareExtensionMessageMapper.errorMessage(
            for: AppError(
                category: .authentication,
                operation: "share_extension.upload_file",
                requestKind: .multipartUpload,
                retryability: .userActionRequired,
                recommendedSurface: .alert
            )
        )

        XCTAssertEqual(
            message,
            ExtensionUserMessageCatalog.message(for: .notAuthenticated)
        )
    }

    func testErrorMessageMapsItemProviderUnsupportedDetailToUnsupportedContent() {
        let itemProviderError = NSError(
            domain: NSItemProvider.errorDomain,
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "unsupported type identifier"]
        )

        let message = ShareExtensionMessageMapper.errorMessage(for: itemProviderError)

        XCTAssertEqual(
            message,
            ExtensionUserMessageCatalog.message(for: .unsupportedContent)
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
}
