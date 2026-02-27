import Foundation
import XCTest
@testable import sideBarShared
@testable import sideBar

private let pendingShareStoreExtensionTestSuiteName = "PendingShareStoreTests"

private func makeStoreForExtensionURLHandlerTests() -> PendingShareStore {
    let defaults = UserDefaults(suiteName: pendingShareStoreExtensionTestSuiteName)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
}

extension PendingShareStoreTests {
    func testExtensionURLMessageHandlerRejectsUnsupportedAction() async {
        let store = makeStoreForExtensionURLHandlerTests()
        let response = await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "other_action",
            urlString: "https://example.com",
            pendingStore: store
        )

        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["code"] as? String, ExtensionMessageCode.unsupportedAction.rawValue)
        XCTAssertEqual(response["error"] as? String, ExtensionUserMessageCatalog.message(for: .unsupportedAction))
    }

    func testExtensionURLMessageHandlerRejectsMissingURL() async {
        let store = makeStoreForExtensionURLHandlerTests()
        let response = await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: nil,
            pendingStore: store
        )

        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["code"] as? String, ExtensionMessageCode.missingURL.rawValue)
        XCTAssertEqual(response["error"] as? String, ExtensionUserMessageCatalog.message(for: .missingURL))
    }

    func testExtensionURLMessageHandlerRefreshesTokenAndRetriesOnUnauthorized() async {
        let store = makeStoreForExtensionURLHandlerTests()
        var attempts = 0
        var refreshCalled = false

        let response = await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: "https://example.com",
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
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["code"] as? String, ExtensionMessageCode.websiteSaved.rawValue)
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(store.loadAll().first?.url, "https://example.com")
    }

    func testExtensionURLMessageHandlerQueuesWebsiteWhenRefreshFails() async {
        let store = makeStoreForExtensionURLHandlerTests()
        var attempts = 0
        var refreshCalled = false

        let response = await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: "https://example.com",
            pendingStore: store,
            saveWebsite: { _ in
                attempts += 1
                throw APIClientError.requestFailed(401)
            },
            refreshAccessToken: {
                refreshCalled = true
                return false
            }
        )

        XCTAssertTrue(refreshCalled)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["code"] as? String, ExtensionMessageCode.savedForLater.rawValue)
        XCTAssertEqual(
            response["message"] as? String,
            ExtensionUserMessageCatalog.message(for: .savedForLater)
        )
        XCTAssertEqual(response["queued"] as? String, "website")
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(store.loadAll().first?.url, "https://example.com")
    }

    func testExtensionURLMessageHandlerQueuesWebsiteWhenMissingToken() async {
        let store = makeStoreForExtensionURLHandlerTests()
        let response = await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: "https://example.com",
            pendingStore: store,
            saveWebsite: { _ in
                throw APIClientError.missingToken
            }
        )

        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["code"] as? String, ExtensionMessageCode.savedForLater.rawValue)
        XCTAssertEqual(
            response["message"] as? String,
            ExtensionUserMessageCatalog.message(for: .savedForLater)
        )
        XCTAssertEqual(response["queued"] as? String, "website")
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(store.loadAll().first?.url, "https://example.com")
    }

    func testExtensionURLMessageHandlerQueuesWebsiteForYouTubeURL() async {
        let store = makeStoreForExtensionURLHandlerTests()
        let response = await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: "https://www.youtube.com/watch?v=abc123xyzAA",
            pendingStore: store,
            saveWebsite: { _ in
                throw URLError(.notConnectedToInternet)
            }
        )

        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["code"] as? String, ExtensionMessageCode.savedForLater.rawValue)
        XCTAssertEqual(response["message"] as? String, ExtensionUserMessageCatalog.message(for: .savedForLater))
        XCTAssertEqual(response["queued"] as? String, "website")
        XCTAssertEqual(store.loadAll().first?.kind, .website)
        XCTAssertEqual(
            store.loadAll().first?.url,
            "https://www.youtube.com/watch?v=abc123xyzAA"
        )
    }

    func testExtensionURLMessageHandlerCanonicalizesYouTubeShortURL() async {
        let store = makeStoreForExtensionURLHandlerTests()
        let response = await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: "https://youtu.be/abc123xyzAA?t=22",
            pendingStore: store,
            saveWebsite: { _ in
                throw URLError(.notConnectedToInternet)
            }
        )

        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(
            store.loadAll().first?.url,
            "https://www.youtube.com/watch?v=abc123xyzAA"
        )
    }

    func testExtensionURLMessageHandlerRejectsIncompleteYouTubeWatchURL() async {
        let store = makeStoreForExtensionURLHandlerTests()
        let response = await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: "https://www.youtube.com/watch",
            pendingStore: store
        )

        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["code"] as? String, ExtensionMessageCode.invalidURL.rawValue)
        XCTAssertEqual(response["error"] as? String, ExtensionUserMessageCatalog.message(for: .invalidURL))
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testShareExtensionURLQueueHandlerQueuesWebsiteForYouTubeURL() {
        let store = makeStoreForExtensionURLHandlerTests()
        let url = URL(string: "https://www.youtube.com/watch?v=abc123xyzAA")!

        let item = ShareExtensionURLQueueHandler.enqueueURLForLater(url, pendingStore: store)

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.kind, .website)
        XCTAssertEqual(store.loadAll().first?.kind, .website)
    }

    func testShareExtensionURLQueueHandlerCanonicalizesYouTubeShortURL() {
        let store = makeStoreForExtensionURLHandlerTests()
        let url = URL(string: "https://youtu.be/abc123xyzAA?t=10")!

        let item = ShareExtensionURLQueueHandler.enqueueURLForLater(url, pendingStore: store)

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.url, "https://www.youtube.com/watch?v=abc123xyzAA")
    }

    func testShareExtensionURLQueueHandlerRejectsInvalidURL() {
        let store = makeStoreForExtensionURLHandlerTests()
        let url = URL(string: "file:///tmp/example.txt")!

        let item = ShareExtensionURLQueueHandler.enqueueURLForLater(url, pendingStore: store)

        XCTAssertNil(item)
        XCTAssertTrue(store.loadAll().isEmpty)
    }
}
