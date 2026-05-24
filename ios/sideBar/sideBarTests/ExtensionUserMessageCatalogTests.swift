import XCTest
import ImageIO
import sideBarShared

final class ExtensionUserMessageCatalogTests: XCTestCase {
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ExtensionUserMessageCatalogTests.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let suiteName,
           let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        super.tearDown()
    }

    func testAllMessageCodesHaveStableFriendlyCopy() {
        let expected: [ExtensionMessageCode: String] = [
            .savedForLater: "Saved for later.",
            .savedForLaterSignInRequired: "Saved for later. Open sideBar and sign in to finish saving.",
            .websiteSaved: "Website saved.",
            .imageSaved: "Image saved.",
            .fileSaved: "File saved.",
            .savingWebsite: "Saving for later...",
            .preparingImage: "Preparing image...",
            .preparingFile: "Preparing file...",
            .uploadingImage: "Uploading image...",
            .uploadingFile: "Uploading file...",
            .unsupportedAction: "This action is not supported.",
            .missingURL: "No active tab URL found.",
            .invalidURL: "That URL is invalid.",
            .noActiveURL: "No active tab URL found.",
            .queueFailed: "Could not save for later.",
            .notAuthenticated: "Please sign in to sideBar first.",
            .invalidBaseUrl: "Invalid API base URL.",
            .invalidSharePayload: "Could not read the shared content.",
            .unsupportedContent: "This content type is not supported.",
            .imageLoadFailed: "Could not load the image.",
            .imageProcessFailed: "Could not process the image.",
            .fileLoadFailed: "Could not load the file.",
            .fileReadFailed: "Could not read the file.",
            .uploadFailed: "Upload failed. Please try again.",
            .networkError: "Network error. Please try again.",
            .unknownFailure: "Something went wrong. Please try again."
        ]

        XCTAssertEqual(Set(expected.keys), Set(ExtensionMessageCode.allCases))
        for code in ExtensionMessageCode.allCases {
            XCTAssertEqual(ExtensionUserMessageCatalog.message(for: code), expected[code])
        }
    }

    func testUploadFailureMessageAvoidsDoublePrefix() {
        let message = ExtensionUserMessageCatalog.uploadFailureMessage(detail: "Upload failed: HTTP 413")
        XCTAssertEqual(message, "Upload failed. Please try again. HTTP 413")
    }

    func testUploadFailureMessageFallsBackWhenDetailShouldNotBeShown() {
        let message = ExtensionUserMessageCatalog.uploadFailureMessage(
            detail: "The operation couldn’t be completed. (NSURLErrorDomain error -1009.)"
        )
        XCTAssertEqual(message, "Upload failed. Please try again.")
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

    func testSanitizedDetailTruncatesLongMessage() {
        let long = String(repeating: "A", count: 200)
        let detail = ExtensionUserMessageCatalog.sanitizedDetail(long)
        XCTAssertEqual(detail?.count, 120)
    }

    func testSharedStorageUnavailableMessageIsActionable() {
        XCTAssertEqual(
            ExtensionUserMessageCatalog.sharedStorageUnavailableMessage(),
            "Could not access shared storage. Open sideBar and try again."
        )
    }

    func testSafariPopupResourcesMatchAcrossTargets() throws {
        let iosResources = extensionResourcesDirectory(
            targetDirectory: "sideBar Safari Extension/Resources"
        )
        let macResources = extensionResourcesDirectory(
            targetDirectory: "sideBar Safari Extension (macOS) Extension/Resources"
        )

        for resource in [
            "popup.html",
            "popup.css",
            "popup.js",
            "manifest.json",
            "background.js",
            "content.js"
        ] {
            let iosText = try resourceText(
                in: iosResources,
                filename: resource
            )
            let macText = try resourceText(
                in: macResources,
                filename: resource
            )
            XCTAssertEqual(
                normalizedResourceText(iosText),
                normalizedResourceText(macText),
                "\(resource) should stay in sync across iOS/macOS Safari popup targets"
            )
        }
    }

    func testSafariPopupMessageMapMatchesSharedCatalog() throws {
        let iosResources = extensionResourcesDirectory(
            targetDirectory: "sideBar Safari Extension/Resources"
        )
        let script = try resourceText(in: iosResources, filename: "popup.js")
        let map = try popupCodeMap(from: script)

        let expected: [String: String] = [
            ExtensionMessageCode.savedForLater.rawValue: ExtensionUserMessageCatalog.message(for: .savedForLater),
            ExtensionMessageCode.savedForLaterSignInRequired.rawValue:
                ExtensionUserMessageCatalog.message(for: .savedForLaterSignInRequired),
            ExtensionMessageCode.websiteSaved.rawValue: ExtensionUserMessageCatalog.message(for: .websiteSaved),
            ExtensionMessageCode.unsupportedAction.rawValue: ExtensionUserMessageCatalog.message(for: .unsupportedAction),
            ExtensionMessageCode.missingURL.rawValue: ExtensionUserMessageCatalog.message(for: .missingURL),
            ExtensionMessageCode.invalidURL.rawValue: ExtensionUserMessageCatalog.message(for: .invalidURL),
            ExtensionMessageCode.noActiveURL.rawValue: ExtensionUserMessageCatalog.message(for: .noActiveURL),
            ExtensionMessageCode.queueFailed.rawValue: ExtensionUserMessageCatalog.message(for: .queueFailed),
            ExtensionMessageCode.notAuthenticated.rawValue: ExtensionUserMessageCatalog.message(for: .notAuthenticated),
            ExtensionMessageCode.invalidBaseUrl.rawValue: ExtensionUserMessageCatalog.message(for: .invalidBaseUrl),
            ExtensionMessageCode.uploadFailed.rawValue: ExtensionUserMessageCatalog.message(for: .uploadFailed),
            ExtensionMessageCode.networkError.rawValue: ExtensionUserMessageCatalog.message(for: .networkError),
            ExtensionMessageCode.unknownFailure.rawValue: ExtensionUserMessageCatalog.message(for: .unknownFailure)
        ]

        XCTAssertEqual(map, expected)
    }

    func testSafariManifestDeclaresToolbarIconSizesAndAssetsExist() throws {
        let resources = extensionResourcesDirectory(
            targetDirectory: "sideBar Safari Extension/Resources"
        )
        let manifestText = try resourceText(in: resources, filename: "manifest.json")
        let manifestData = Data(manifestText.utf8)
        let manifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: manifestData, options: []) as? [String: Any]
        )

        let icons = try XCTUnwrap(manifest["icons"] as? [String: String])
        for size in ["16", "32", "48", "96", "128", "256", "512"] {
            let path = try XCTUnwrap(icons[size], "Expected icons[\(size)] in manifest.json")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: resources.appendingPathComponent(path).path),
                "Missing icon asset for size \(size): \(path)"
            )
        }

        let action = try XCTUnwrap(manifest["action"] as? [String: Any])
        let defaultIcon = try XCTUnwrap(action["default_icon"] as? [String: String])
        for size in ["16", "32", "48", "96"] {
            let path = try XCTUnwrap(defaultIcon[size], "Expected action.default_icon[\(size)] in manifest.json")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: resources.appendingPathComponent(path).path),
                "Missing action icon asset for size \(size): \(path)"
            )
        }
    }

    func testSafariManifestIconsFillTheirCanvasWithoutTransparentPadding() throws {
        for iconDirectory in [
            repositoryDirectory().appendingPathComponent("assets/safari-extension"),
            extensionResourcesDirectory(targetDirectory: "sideBar Safari Extension/Resources/images"),
            extensionResourcesDirectory(targetDirectory: "sideBar Safari Extension (macOS) Extension/Resources/images")
        ] {
            for size in [16, 32, 48, 64, 96, 128, 256, 512] {
                let iconURL = iconDirectory.appendingPathComponent("icon-\(size).png")
                let bounds = try alphaBounds(forPNGAt: iconURL)

                XCTAssertEqual(
                    bounds,
                    CGRect(x: 0, y: 0, width: size, height: size),
                    "\(iconURL.path) should fill its canvas so Safari does not compound icon padding inside system icon wells."
                )
            }
        }
    }

    func testMacSafariContainingAppDeclaresLaunchServicesIconSet() throws {
        let iconSetDirectory = extensionResourcesDirectory(
            targetDirectory: "sideBar Safari Extension (macOS)/Assets.xcassets/AppIcon.appiconset"
        )
        let contentsText = try resourceText(in: iconSetDirectory, filename: "Contents.json")
        let contentsData = Data(contentsText.utf8)
        let contents = try JSONDecoder().decode(AppIconSetContents.self, from: contentsData)
        let macImages = contents.images.filter { $0.idiom == "mac" }
        let declaredSizes = Set(macImages.map(\.launchServicesKey))
        let requiredSizes: Set<String> = [
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
        ]

        XCTAssertEqual(declaredSizes, requiredSizes)
        for image in macImages {
            let filename = try XCTUnwrap(image.filename, "Missing filename for \(image.launchServicesKey)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: iconSetDirectory.appendingPathComponent(filename).path),
                "Missing macOS Safari containing app icon asset: \(filename)"
            )
        }
    }

    func testQueueResultMapperReturnsQueueFailedWhenItemIsMissing() {
        let message = ExtensionQueueResultMapper.queueMessage(for: nil)
        XCTAssertFalse(ExtensionQueueResultMapper.queueSucceeded(for: nil))
        XCTAssertEqual(message, ExtensionUserMessageCatalog.message(for: .queueFailed))
    }

    func testQueueResultMapperReturnsSavedForLaterWhenItemExists() {
        let item = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: Date(),
            url: "https://example.com"
        )
        let message = ExtensionQueueResultMapper.queueMessage(for: item)
        XCTAssertTrue(ExtensionQueueResultMapper.queueSucceeded(for: item))
        XCTAssertEqual(message, ExtensionUserMessageCatalog.message(for: .savedForLater))
    }

    func testQueueWriteFailureFallsBackToQueueFailedCopy() {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected test user defaults suite")
            return
        }
        let store = PendingShareStore(
            baseDirectory: URL(fileURLWithPath: "/dev/null"),
            userDefaults: defaults
        )
        let item = store.enqueueFile(
            data: Data("payload".utf8),
            filename: "test.txt",
            mimeType: "text/plain",
            kind: .file
        )

        XCTAssertNil(item)
        XCTAssertEqual(
            ExtensionQueueResultMapper.queueMessage(for: item),
            ExtensionUserMessageCatalog.message(for: .queueFailed)
        )
    }

    func testNetworkErrorClassifierMapsTimeoutToNetworkErrorCode() {
        let code = ExtensionNetworkErrorClassifier.messageCode(for: URLError(.timedOut))
        XCTAssertEqual(code, .networkError)
    }

    func testNetworkErrorClassifierMapsOfflineNSErrorToNetworkErrorCode() {
        let nsError = NSError(
            domain: NSURLErrorDomain,
            code: URLError.notConnectedToInternet.rawValue
        )
        let code = ExtensionNetworkErrorClassifier.messageCode(for: nsError)
        XCTAssertEqual(code, .networkError)
        XCTAssertEqual(
            ExtensionUserMessageCatalog.message(for: .networkError),
            "Network error. Please try again."
        )
    }

    private func extensionResourcesDirectory(targetDirectory: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(targetDirectory)
    }

    private func repositoryDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func resourceText(in directory: URL, filename: String) throws -> String {
        let fileURL = directory.appendingPathComponent(filename)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func normalizedResourceText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
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

    private func popupCodeMap(from script: String) throws -> [String: String] {
        guard let mapStart = script.range(of: "const CODE_TO_MESSAGE = {"),
              let mapEnd = script.range(of: "};", range: mapStart.upperBound..<script.endIndex) else {
            XCTFail("Could not find CODE_TO_MESSAGE in popup.js")
            return [:]
        }

        let mapBody = String(script[mapStart.upperBound..<mapEnd.lowerBound])
        let regex = try NSRegularExpression(pattern: #"([a-z_]+)\s*:\s*"([^"]+)""#)
        let nsRange = NSRange(mapBody.startIndex..<mapBody.endIndex, in: mapBody)
        let matches = regex.matches(in: mapBody, range: nsRange)

        var map: [String: String] = [:]
        for match in matches {
            guard let codeRange = Range(match.range(at: 1), in: mapBody),
                  let messageRange = Range(match.range(at: 2), in: mapBody) else {
                continue
            }
            map[String(mapBody[codeRange])] = String(mapBody[messageRange])
        }
        return map
    }
}

private struct AppIconSetContents: Decodable {
    let images: [AppIconSetImage]
}

private struct AppIconSetImage: Decodable {
    let filename: String?
    let idiom: String
    let scale: String?
    let size: String

    var launchServicesKey: String {
        "\(size)@\(scale ?? "1x")"
    }
}
