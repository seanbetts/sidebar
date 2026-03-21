import Foundation
import XCTest
@testable import ShareExtension
import sideBarShared

final class ShareExtensionCoverageTests: XCTestCase {
    func testShareExtensionInfoPlistSupportsSafariWebpagesAndRichAttachmentPayloads() throws {
        let repositoryRoot = try findRepositoryRoot()
        let plistURL = repositoryRoot.appendingPathComponent("ios/sideBar/ShareExtension/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let extensionDictionary = try XCTUnwrap(propertyList["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionDictionary["NSExtensionAttributes"] as? [String: Any])
        let activationRule = try XCTUnwrap(attributes["NSExtensionActivationRule"] as? [String: Any])

        XCTAssertEqual(activationRule["NSExtensionActivationSupportsAttachmentsWithMaxCount"] as? Int, 10)
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsFileWithMaxCount"] as? Int, 10)
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsImageWithMaxCount"] as? Int, 10)
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsURLWithMaxCount"] as? Int, 10)
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsWebPageWithMaxCount"] as? Int, 1)
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsWebURLWithMaxCount"] as? Int, 10)
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsText"] as? Bool, true)
    }

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

    func testExtractFirstURLFindsURLInPlainText() {
        let controller = ShareViewController()
        let text = "Please review https://example.com/docs?tab=1 before launch."

        let url = controller.extractFirstURL(from: text)

        XCTAssertEqual(url?.absoluteString, "https://example.com/docs?tab=1")
    }

    func testNormalizedWebsiteEventURLCanonicalizesYouTubeURL() {
        let controller = ShareViewController()
        let url = URL(string: "https://youtu.be/abc123xyzAA?t=14&si=test")!

        let normalized = controller.normalizedWebsiteEventURL(url)

        XCTAssertEqual(normalized, "https://www.youtube.com/watch?v=abc123xyzAA")
    }

    @MainActor
    func testShowSaveURLResultDefaultsToSavedForLaterForShareExtensionWebsites() {
        let controller = ShareViewController()
        controller.loadViewIfNeeded()

        controller.showSaveURLResult(["ok": true])

        let label = controller.view.firstSubview(where: { $0 is UILabel }) as? UILabel
        XCTAssertEqual(label?.text, ExtensionUserMessageCatalog.message(for: .savedForLater))
    }

    func testMimeTypeForFilenameUsesKnownAndFallbackMappings() {
        let controller = ShareViewController()

        XCTAssertEqual(
            controller.mimeTypeForFilename("presentation.pptx"),
            "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        )
        XCTAssertEqual(controller.mimeTypeForFilename("unknown.custom"), "application/octet-stream")
    }

    func testProcessSharedContentRecordsEntryDiagnosticsBeforeProviderParsing() {
        ExternalSurfaceDiagnosticsStore.shared.clear()
        defer { ExternalSurfaceDiagnosticsStore.shared.clear() }

        let controller = ShareViewController()
        controller.loadViewIfNeeded()

        controller.processSharedContent()

        let export = ExternalSurfaceDiagnosticsStore.shared.exportText(limit: 10)
        XCTAssertTrue(export.contains("[share_extension] begin_request: Began processing shared content."))
        XCTAssertTrue(export.contains("item_provider_count=0"))
    }

    func testShareNetworkMonitorUsesSharedSessionForConnectivityProbes() {
        XCTAssertTrue(ShareNetworkMonitor.defaultSession() === URLSession.shared)
    }

    private func findRepositoryRoot(filePath: String = #filePath) throws -> URL {
        var candidate = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while candidate.path != "/" {
            let projectFile = candidate
                .appendingPathComponent("ios/sideBar/sideBar.xcodeproj/project.pbxproj")
            if FileManager.default.fileExists(atPath: projectFile.path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw NSError(domain: "ShareExtensionCoverageTests", code: 1)
    }
}

private extension UIView {
    func firstSubview(where predicate: (UIView) -> Bool) -> UIView? {
        if predicate(self) {
            return self
        }
        for child in subviews {
            if let match = child.firstSubview(where: predicate) {
                return match
            }
        }
        return nil
    }
}
