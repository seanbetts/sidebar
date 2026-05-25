import Foundation
import ImageIO
import XCTest
@testable import ShareExtension
import sideBarShared
import UniformTypeIdentifiers
import UIKit

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

    func testShareExtensionDownsamplesFileBackedImagesBeforeUpload() throws {
        let sourceURL = try makeTemporaryPNGURL(size: CGSize(width: 2_600, height: 1_800))

        let prepared = try XCTUnwrap(
            ShareImageFilePreparer.downsampledUploadImage(
                from: sourceURL,
                filename: "large.png"
            )
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: prepared.fileURL)
        }

        XCTAssertEqual(prepared.filename, "large.jpg")
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertNotEqual(prepared.fileURL, sourceURL)
        XCTAssertLessThanOrEqual(
            try maxPixelDimension(of: prepared.fileURL),
            ShareImageFilePreparer.maxUploadPixelSize
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

    private func makeTemporaryPNGURL(size: CGSize) throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: size)
        let data = renderer.pngData { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func maxPixelDimension(of url: URL) throws -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            XCTFail("Expected readable image properties for \(url.path)")
            return 0
        }
        return max(width, height)
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
