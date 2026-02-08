import XCTest
import sideBarShared

final class ExtensionUserMessageCatalogTests: XCTestCase {
    private let suiteName = "ExtensionUserMessageCatalogTests"

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    func testAllMessageCodesHaveStableFriendlyCopy() {
        let expected: [ExtensionMessageCode: String] = [
            .savedForLater: "Saved for later.",
            .websiteSaved: "Website saved.",
            .imageSaved: "Image saved.",
            .fileSaved: "File saved.",
            .savingWebsite: "Saving website...",
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

    func testSafariPopupResourcesMatchAcrossTargets() throws {
        let iosResources = extensionResourcesDirectory(
            targetDirectory: "sideBar Safari Extension/Resources"
        )
        let macResources = extensionResourcesDirectory(
            targetDirectory: "sideBar Safari Extension (macOS) Extension/Resources"
        )

        for resource in ["popup.html", "popup.css", "popup.js"] {
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
            ExtensionMessageCode.unsupportedAction.rawValue: ExtensionUserMessageCatalog.message(for: .unsupportedAction),
            ExtensionMessageCode.missingURL.rawValue: ExtensionUserMessageCatalog.message(for: .missingURL),
            ExtensionMessageCode.invalidURL.rawValue: ExtensionUserMessageCatalog.message(for: .invalidURL),
            ExtensionMessageCode.noActiveURL.rawValue: ExtensionUserMessageCatalog.message(for: .noActiveURL),
            ExtensionMessageCode.queueFailed.rawValue: ExtensionUserMessageCatalog.message(for: .queueFailed),
            ExtensionMessageCode.notAuthenticated.rawValue: ExtensionUserMessageCatalog.message(for: .notAuthenticated),
            ExtensionMessageCode.networkError.rawValue: ExtensionUserMessageCatalog.message(for: .networkError),
            ExtensionMessageCode.unknownFailure.rawValue: ExtensionUserMessageCatalog.message(for: .unknownFailure)
        ]

        XCTAssertEqual(map, expected)
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

    private func resourceText(in directory: URL, filename: String) throws -> String {
        let fileURL = directory.appendingPathComponent(filename)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func normalizedResourceText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
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
