import Foundation
import XCTest
@testable import ShareExtension
import sideBarShared
import UniformTypeIdentifiers

final class ShareViewControllerCoverageTests: XCTestCase {
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

    func testShareExtensionRejectsOversizedInMemoryProviderFallbacks() {
        XCTAssertTrue(ShareExtensionPayloadSizePolicy.acceptsInMemoryPayload(byteCount: 1024))
        XCTAssertTrue(
            ShareExtensionPayloadSizePolicy.acceptsInMemoryPayload(
                byteCount: ShareExtensionPayloadSizePolicy.maxInMemoryPayloadBytes
            )
        )
        XCTAssertFalse(
            ShareExtensionPayloadSizePolicy.acceptsInMemoryPayload(
                byteCount: ShareExtensionPayloadSizePolicy.maxInMemoryPayloadBytes + 1
            )
        )
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

    func testShareExtensionUploadHandlingDoesNotUseReachabilityPreflight() throws {
        let repositoryRoot = try findRepositoryRoot()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ios/sideBar/ShareExtension/ShareViewController+MediaHandling.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("ShareNetworkMonitor"))
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
