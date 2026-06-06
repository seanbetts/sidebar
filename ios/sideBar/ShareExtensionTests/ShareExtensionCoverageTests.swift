import Foundation
import ImageIO
import XCTest
@testable import ShareExtension
import sideBarShared
import UniformTypeIdentifiers

final class ShareExtensionCoverageTests: XCTestCase {
    func testShareExtensionInfoPlistAllowsMultiProviderWebSharesAndSingleMediaFiles() throws {
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
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsFileWithMaxCount"] as? Int, 1)
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsImageWithMaxCount"] as? Int, 1)
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
            "ios/sideBar/ShareExtension/Assets.xcassets/AppIcon.appiconset/Contents.json"
        )
        let iconContentsData = try Data(contentsOf: iconContentsURL)
        let iconContents = try JSONDecoder().decode(AppIconSetContents.self, from: iconContentsData)
        let iconDirectoryURL = iconContentsURL.deletingLastPathComponent()
        let macImagesByKey = Dictionary(
            uniqueKeysWithValues: iconContents.images
                .filter { $0.idiom == "mac" }
                .map { ($0.launchServicesKey, $0) }
        )
        let requiredMacIconKeys = Set([
            "16x16@1x",
            "16x16@2x",
            "32x32@1x",
            "32x32@2x",
            "128x128@1x",
            "128x128@2x",
            "256x256@1x",
            "256x256@2x",
            "512x512@1x",
            "512x512@2x"
        ])

        XCTAssertEqual(Set(macImagesByKey.keys), requiredMacIconKeys)

        for iconKey in requiredMacIconKeys {
            let image = try XCTUnwrap(macImagesByKey[iconKey], iconKey)
            let filename = try XCTUnwrap(image.filename, iconKey)
            let fileURL = iconDirectoryURL.appendingPathComponent(filename)

            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fileURL.path),
                "Missing ShareExtension AppIcon file \(filename)"
            )
        }

        let iosImages = iconContents.images.filter {
            $0.idiom == "universal" && $0.platform == "ios" && $0.size == "1024x1024"
        }
        XCTAssertEqual(Set(iosImages.compactMap(\.filename)), Set([
            "icon-1024.png",
            "icon-1024-dark.png",
            "icon-1024-tinted.png"
        ]))
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

    func testShareExtensionMacAppIconsFillCanvasForSafariShareMenu() throws {
        let repositoryRoot = try findRepositoryRoot()
        let shareIconDirectory = repositoryRoot.appendingPathComponent(
            "ios/sideBar/ShareExtension/Assets.xcassets/AppIcon.appiconset"
        )
        let iconFilenamesByPixelSize = [
            "Icon-macOS-Default-16x16@1x.png": 16,
            "Icon-macOS-Default-16x16@2x.png": 32,
            "Icon-macOS-Default-32x32@1x.png": 32,
            "Icon-macOS-Default-32x32@2x.png": 64,
            "Icon-macOS-Default-128x128@1x.png": 128,
            "Icon-macOS-Default-128x128@2x.png": 256,
            "Icon-macOS-Default-256x256@1x.png": 256,
            "Icon-macOS-Default-256x256@2x.png": 512,
            "Icon-macOS-Default-512x512@1x.png": 512,
            "Icon-macOS-Default-1024x1024@1x.png": 1024
        ]

        for (filename, pixelSize) in iconFilenamesByPixelSize {
            let iconURL = shareIconDirectory.appendingPathComponent(filename)
            let bounds = try alphaBounds(forPNGAt: iconURL)

            XCTAssertEqual(
                bounds,
                CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
                "\(filename) must fill its canvas because Safari's share menu puts the extension icon inside its own icon well."
            )
        }
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

    func testShareExtensionUploadUsesSharedAPIClientExecution() throws {
        let repositoryRoot = try findRepositoryRoot()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "ios/sideBar/ShareExtension/ShareExtensionEnvironment.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("apiClient.executeUpload("))
        XCTAssertFalse(source.contains("session.upload(for:"))
    }

    func testShareExtensionImageHandlingPrefersFileRepresentationBeforeDecoding() throws {
        let repositoryRoot = try findRepositoryRoot()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "ios/sideBar/ShareExtension/ShareViewController+MediaHandling.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        let fileRepresentationRange = try XCTUnwrap(
            source.range(
                of: "letfileURLResult=awaitloadFileURLResult(from:itemProvider,typeIdentifier:UTType.image.identifier)"
            )
        )
        let decodeRange = try XCTUnwrap(source.range(of: "letimageResult=awaitloadImageResult(from:itemProvider)"))

        XCTAssertLessThan(fileRepresentationRange.lowerBound, decodeRange.lowerBound)
        XCTAssertTrue(source.contains("awaituploadFileFromURL(fileURL,itemProvider:itemProvider,isImage:true)"))
        XCTAssertTrue(source.contains("ShareExtensionPayloadSizePolicy.acceptsInMemoryPayload(byteCount:data.count)"))
    }

    func testWidgetProvidersClassifyRefreshFailuresAsWidgetRefreshRequests() throws {
        let repositoryRoot = try findRepositoryRoot()
        let providerPaths = [
            "ios/sideBar/sideBarWidgets/Providers/TodayTasksProvider.swift",
            "ios/sideBar/sideBarWidgets/Providers/PinnedNotesProvider.swift",
            "ios/sideBar/sideBarWidgets/Providers/PinnedFilesProvider.swift",
            "ios/sideBar/sideBarWidgets/Providers/SavedSitesProvider.swift"
        ]

        for providerPath in providerPaths {
            let sourceURL = repositoryRoot.appendingPathComponent(providerPath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            XCTAssertTrue(source.contains("requestKind: .widgetRefresh"), providerPath)
            XCTAssertFalse(source.contains("requestKind: .foregroundRead"), providerPath)
        }
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

    private func alphaBounds(forPNGAt fileURL: URL) throws -> CGRect {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Could not decode PNG at \(fileURL.path)")
            return .null
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            XCTFail("Could not create bitmap context for \(fileURL.path)")
            return .null
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for row in 0..<height {
            for column in 0..<width {
                let alphaIndex = ((row * width) + column) * 4 + 3
                if pixels[alphaIndex] > 0 {
                    minX = min(minX, column)
                    minY = min(minY, row)
                    maxX = max(maxX, column)
                    maxY = max(maxY, row)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return .null
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

private struct AppIconSetContents: Decodable {
    let images: [AppIconSetImage]
}

private struct AppIconSetImage: Decodable {
    let filename: String?
    let idiom: String
    let platform: String?
    let scale: String?
    let size: String

    var launchServicesKey: String {
        "\(size)@\(scale ?? "1x")"
    }
}
