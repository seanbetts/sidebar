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

    func testResponsePayloadRejectsUnsupportedActionWhenMessageIsMissing() {
        let store = makeStore()

        let payload = SafariExtensionMessageHandler.responsePayload(for: nil, pendingStore: store)

        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.unsupportedAction.rawValue)
        XCTAssertEqual(payload["error"] as? String, ExtensionUserMessageCatalog.message(for: .unsupportedAction))
    }

    func testResponsePayloadQueuesCanonicalYouTubeURL() {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url",
            "url": "https://youtu.be/abc123xyzAA?t=35"
        ]

        let payload = SafariExtensionMessageHandler.responsePayload(for: message, pendingStore: store)

        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.savedForLater.rawValue)
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(store.loadAll().first?.url, "https://www.youtube.com/watch?v=abc123xyzAA")
    }

    func testResponsePayloadRejectsMissingURL() {
        let store = makeStore()
        let message: [String: Any] = [
            "action": "save_url"
        ]

        let payload = SafariExtensionMessageHandler.responsePayload(for: message, pendingStore: store)

        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.missingURL.rawValue)
        XCTAssertEqual(payload["error"] as? String, ExtensionUserMessageCatalog.message(for: .missingURL))
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    private func makeStore() -> PendingShareStore {
        let defaults = UserDefaults(suiteName: suiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
    }
}
