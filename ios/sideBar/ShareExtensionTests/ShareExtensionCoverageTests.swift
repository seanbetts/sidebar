import Foundation
import XCTest
@testable import ShareExtension
import sideBarShared
import UniformTypeIdentifiers

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

    func testShareExtensionInfoPlistConfiguresSafariPreprocessingFile() throws {
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

        XCTAssertEqual(
            attributes["NSExtensionJavaScriptPreprocessingFile"] as? String,
            "ShareExtensionPreprocessing"
        )
    }

    func testShareExtensionUsesMacAppIconAssets() throws {
        let repositoryRoot = try findRepositoryRoot()
        let projectURL = repositoryRoot.appendingPathComponent("ios/sideBar/sideBar.xcodeproj/project.pbxproj")
        let projectContents = try String(contentsOf: projectURL, encoding: .utf8)

        let shareExtensionConfigurations = projectContents.components(
            separatedBy: "INFOPLIST_FILE = ShareExtension/Info.plist;"
        )
        XCTAssertGreaterThanOrEqual(shareExtensionConfigurations.count, 3)
        XCTAssertTrue(
            shareExtensionConfigurations.dropFirst().dropLast().allSatisfy {
                $0.contains("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
            }
        )

        let iconContentsURL = repositoryRoot.appendingPathComponent(
            "ios/sideBar/sideBar/Assets.xcassets/AppIcon.appiconset/Contents.json"
        )
        let iconContentsData = try Data(contentsOf: iconContentsURL)
        let iconContents = try XCTUnwrap(
            JSONSerialization.jsonObject(with: iconContentsData) as? [String: Any]
        )
        let images = try XCTUnwrap(iconContents["images"] as? [[String: Any]])

        XCTAssertTrue(
            images.contains {
                ($0["idiom"] as? String) == "mac"
            }
        )
    }

    func testShareExtensionTargetDoesNotExcludeSharedAssetCatalog() throws {
        let repositoryRoot = try findRepositoryRoot()
        let projectURL = repositoryRoot.appendingPathComponent("ios/sideBar/sideBar.xcodeproj/project.pbxproj")
        let projectContents = try String(contentsOf: projectURL, encoding: .utf8)

        let marker = #"Exceptions for "sideBar" folder in "ShareExtension" target"#
        let markerRange = try XCTUnwrap(projectContents.range(of: marker))
        let suffix = projectContents[markerRange.lowerBound...]
        let blockContents = String(suffix.prefix(400))

        XCTAssertFalse(blockContents.contains("Assets.xcassets"))
    }

    func testOnlyAppTargetLinksVendoredSentryFramework() throws {
        let repositoryRoot = try findRepositoryRoot()
        let projectURL = repositoryRoot.appendingPathComponent("ios/sideBar/sideBar.xcodeproj/project.pbxproj")
        let projectContents = try String(contentsOf: projectURL, encoding: .utf8)

        let sentryBuildFileLines = projectContents
            .components(separatedBy: .newlines)
            .filter {
                $0.contains("/* Vendor/Sentry/Sentry.xcframework in Frameworks */ = {isa = PBXBuildFile;")
            }

        XCTAssertEqual(sentryBuildFileLines.count, 1)
        XCTAssertTrue(
            projectBlockContents(
                in: projectContents,
                marker: "\t\t14C84A452F10562300FE0C16 /* Frameworks */ = {"
            ).contains("Vendor/Sentry/Sentry.xcframework in Frameworks")
        )
        XCTAssertFalse(
            projectBlockContents(
                in: projectContents,
                marker: "\t\t142516AA2F1EB96B0072E4F9 /* Frameworks */ = {"
            ).contains("Vendor/Sentry/Sentry.xcframework in Frameworks")
        )
        XCTAssertFalse(
            projectBlockContents(
                in: projectContents,
                marker: "\t\t1448E6C42F27A6420066EE47 /* Frameworks */ = {"
            ).contains("Vendor/Sentry/Sentry.xcframework in Frameworks")
        )
        XCTAssertFalse(
            projectBlockContents(
                in: projectContents,
                marker: "\t\t146EA0562F2FE83C004AE7D1 /* Frameworks */ = {"
            ).contains("Vendor/Sentry/Sentry.xcframework in Frameworks")
        )
        XCTAssertFalse(
            projectBlockContents(
                in: projectContents,
                marker: "\t\t146EA0932F2FE878004AE7D1 /* Frameworks */ = {"
            ).contains("Vendor/Sentry/Sentry.xcframework in Frameworks")
        )
    }

    func testWidgetsExtensionEntitlementsIncludeSharedKeychainAccessGroup() throws {
        let repositoryRoot = try findRepositoryRoot()
        let entitlementsPath = repositoryRoot
            .appendingPathComponent("ios/sideBar/sideBarWidgetsExtension.entitlements")
            .path
        let content = try String(contentsOfFile: entitlementsPath, encoding: .utf8)
        let projectContents = try String(
            contentsOf: repositoryRoot.appendingPathComponent("ios/sideBar/sideBar.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let staleEntitlementsPath = repositoryRoot
            .appendingPathComponent("ios/sideBar/sideBarWidgets/sideBarWidgets.entitlements")
            .path

        XCTAssertTrue(content.contains("<string>$(KEYCHAIN_ACCESS_GROUP)</string>"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleEntitlementsPath))
        XCTAssertFalse(projectContents.contains("sideBarWidgets/sideBarWidgets.entitlements"))
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

    func testWebsiteProvidersWithJavaScriptResultsAreNotClassifiedAsBinaryFiles() {
        let controller = ShareViewController()
        let itemProvider = NSItemProvider()
        itemProvider.registerDataRepresentation(forTypeIdentifier: UTType.data.identifier, visibility: .all) { completion in
            completion(Data("ignored".utf8), nil)
            return nil
        }
        itemProvider.registerItem(
            forTypeIdentifier: UTType.propertyList.identifier,
            loadHandler: { completion, _, _ in
                completion?(
                    [
                        NSExtensionJavaScriptPreprocessingResultsKey: [
                            "baseURI": "https://example.com/article"
                        ]
                    ] as NSSecureCoding,
                    nil
                )
            }
        )

        XCTAssertFalse(controller.hasBinaryFileContent(itemProvider))
    }

    func testGenericDataProvidersRemainClassifiedAsBinaryFiles() {
        let controller = ShareViewController()
        let itemProvider = NSItemProvider()
        itemProvider.registerDataRepresentation(forTypeIdentifier: UTType.data.identifier, visibility: .all) { completion in
            completion(Data("file".utf8), nil)
            return nil
        }

        XCTAssertTrue(controller.hasBinaryFileContent(itemProvider))
    }

    func testURLFromTextPayloadReadsSafariJavaScriptPreprocessingResults() {
        let controller = ShareViewController()
        let payload: [String: Any] = [
            NSExtensionJavaScriptPreprocessingResultsKey: [
                "baseURI": "https://example.com/article?ref=share"
            ]
        ]

        let url = controller.urlFromTextPayload(payload)

        XCTAssertEqual(url?.absoluteString, "https://example.com/article?ref=share")
    }

    func testNormalizedWebsiteEventURLCanonicalizesYouTubeURL() {
        let controller = ShareViewController()
        let url = URL(string: "https://youtu.be/abc123xyzAA?t=14&si=test")!

        let normalized = controller.normalizedWebsiteEventURL(url)

        XCTAssertEqual(normalized, "https://www.youtube.com/watch?v=abc123xyzAA")
    }

    func testShareExtensionURLFlowUsesQueueOnlySaveStrategy() throws {
        let repositoryRoot = try findRepositoryRoot()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ios/sideBar/ShareExtension/ShareViewController+URLHandling.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("saveStrategy: .queueOnly"))
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

    private func projectBlockContents(
        in projectContents: String,
        marker: String
    ) -> String {
        guard let markerRange = projectContents.range(of: marker) else {
            return ""
        }
        let suffix = projectContents[markerRange.lowerBound...]
        guard let blockEnd = suffix.range(of: "\n\t\t};") else {
            return String(suffix)
        }
        return String(suffix[..<blockEnd.upperBound])
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
