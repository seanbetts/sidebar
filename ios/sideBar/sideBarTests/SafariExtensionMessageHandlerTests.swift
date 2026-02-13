import Foundation
import XCTest
@testable import sideBarShared

final class SafariExtensionMessageHandlerTests: XCTestCase {
    private let suiteName = "SafariExtensionMessageHandlerTests"

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    func testResponsePayloadRejectsUnsupportedActionWhenMessageIsMissing() async {
        let store = makeStore()

        let payload = await SafariExtensionMessageHandler.responsePayload(for: nil, pendingStore: store)

        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.unsupportedAction.rawValue)
        XCTAssertEqual(payload["error"] as? String, ExtensionUserMessageCatalog.message(for: .unsupportedAction))
    }

    func testResponsePayloadQueuesCanonicalYouTubeURL() async {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url",
            "url": "https://youtu.be/abc123xyzAA?t=35"
        ]

        let payload = await SafariExtensionMessageHandler.responsePayload(
            for: message,
            pendingStore: store,
            saveWebsite: { _ in
                throw URLError(.notConnectedToInternet)
            }
        )

        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.savedForLater.rawValue)
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(store.loadAll().first?.url, "https://www.youtube.com/watch?v=abc123xyzAA")
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

    func testResponsePayloadReturnsErrorWhenBackendSaveFails() async {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url",
            "url": "https://example.com/article"
        ]

        let payload = await SafariExtensionMessageHandler.responsePayload(
            for: message,
            pendingStore: store,
            saveWebsite: { _ in
                throw APIClientError.apiError("Unable to save website")
            }
        )

        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.uploadFailed.rawValue)
        XCTAssertEqual(
            payload["error"] as? String,
            ExtensionUserMessageCatalog.uploadFailureMessage(detail: "Unable to save website")
        )
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testResponsePayloadRefreshesAndRetriesOnUnauthorized() async {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url",
            "url": "https://example.com/article"
        ]
        var attempts = 0
        var refreshCalled = false

        let payload = await SafariExtensionMessageHandler.responsePayload(
            for: message,
            pendingStore: store,
            saveWebsite: { _ in
                attempts += 1
                if attempts == 1 {
                    throw APIClientError.requestFailed(401)
                }
            },
            refreshAccessToken: {
                refreshCalled = true
                return true
            }
        )

        XCTAssertTrue(refreshCalled)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.websiteSaved.rawValue)
    }

    private func makeStore() -> PendingShareStore {
        let defaults = UserDefaults(suiteName: suiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
    }
}
