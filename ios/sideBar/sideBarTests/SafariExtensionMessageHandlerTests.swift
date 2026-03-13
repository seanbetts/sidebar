import Foundation
import XCTest
@testable import sideBarShared

final class SafariExtensionMessageHandlerTests: XCTestCase {
    private var suiteName: String!
    private var directoriesToRemove: [URL] = []

    override func setUp() {
        super.setUp()
        suiteName = "SafariExtensionMessageHandlerTests.\(UUID().uuidString)"
        directoriesToRemove = []
    }

    override func tearDown() {
        if let suiteName,
           let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        for directory in directoriesToRemove {
            try? FileManager.default.removeItem(at: directory)
        }
        directoriesToRemove.removeAll()
        suiteName = nil
        super.tearDown()
    }

    func testResponsePayloadRejectsUnsupportedActionWhenMessageIsMissing() async {
        let store = makeStore()

        let payload = await SafariExtensionMessageHandler.responsePayload(for: nil, pendingStore: store)

        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.unsupportedAction.rawValue)
        XCTAssertEqual(payload["error"] as? String, ExtensionUserMessageCatalog.message(for: .unsupportedAction))
    }

    func testResponsePayloadSavesCanonicalYouTubeURLImmediately() async {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url",
            "url": "https://youtu.be/abc123xyzAA?t=35"
        ]
        var savedURL: String?

        let payload = await SafariExtensionMessageHandler.responsePayload(
            for: message,
            pendingStore: store,
            saveWebsite: { url in
                savedURL = url
            }
        )

        XCTAssertEqual(savedURL, "https://www.youtube.com/watch?v=abc123xyzAA")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.websiteSaved.rawValue)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testResponsePayloadRejectsMissingURL() async {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url"
        ]

        let payload = await SafariExtensionMessageHandler.responsePayload(for: message, pendingStore: store)

        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.missingURL.rawValue)
        XCTAssertEqual(payload["error"] as? String, ExtensionUserMessageCatalog.message(for: .missingURL))
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testResponsePayloadFailsWhenSaveClosureReturnsNonRetryableAPIError() async {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url",
            "url": "https://example.com/article"
        ]

        let payload = await SafariExtensionMessageHandler.responsePayload(
            for: message,
            pendingStore: store,
            saveWebsite: { _ in
                throw APIClientError.apiError("Invalid URL")
            }
        )

        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.uploadFailed.rawValue)
        XCTAssertEqual(
            payload["error"] as? String,
            ExtensionUserMessageCatalog.message(for: .uploadFailed)
        )
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testResponsePayloadQueuesWhenSaveClosureReturnsRetryableAPIError() async {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url",
            "url": "https://example.com/article"
        ]

        let payload = await SafariExtensionMessageHandler.responsePayload(
            for: message,
            pendingStore: store,
            saveWebsite: { _ in
                throw APIClientError.apiError("Temporary upstream timeout, try again")
            }
        )

        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.savedForLater.rawValue)
        XCTAssertEqual(
            payload["message"] as? String,
            ExtensionUserMessageCatalog.message(for: .savedForLater)
        )
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(store.loadAll().first?.url, "https://example.com/article")
    }

    func testResponsePayloadRetriesSaveAfterUnauthorizedRefresh() async {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url",
            "url": "https://example.com/article"
        ]
        var saveCallCount = 0
        var refreshCallCount = 0

        let payload = await SafariExtensionMessageHandler.responsePayload(
            for: message,
            pendingStore: store,
            saveWebsite: { _ in
                saveCallCount += 1
                if saveCallCount == 1 {
                    throw APIClientError.requestFailed(403)
                }
            },
            refreshAccessToken: {
                refreshCallCount += 1
                return true
            }
        )

        XCTAssertEqual(saveCallCount, 2)
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.websiteSaved.rawValue)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    private func makeStore() -> PendingShareStore {
        let defaults = UserDefaults(suiteName: suiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directoriesToRemove.append(directory)
        return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
    }
}
