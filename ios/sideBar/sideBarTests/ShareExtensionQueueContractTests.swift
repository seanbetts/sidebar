import Foundation
import XCTest
@testable import sideBarShared

final class ShareExtensionQueueContractTests: XCTestCase {
    private var suiteName: String!
    private var directoriesToRemove: [URL] = []

    override func setUp() {
        super.setUp()
        suiteName = "ShareExtensionQueueContractTests.\(UUID().uuidString)"
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

    func testQueueHandlerNormalizesBareHostToHttpsURL() {
        let store = makeStore()
        let url = URL(string: "example.com")!

        let queued = ShareExtensionURLQueueHandler.enqueueURLForLater(url, pendingStore: store)

        XCTAssertNotNil(queued)
        XCTAssertEqual(store.loadAll().first?.url, "https://example.com")
        XCTAssertEqual(store.loadAll().first?.kind, .website)
    }

    func testQueueHandlerRejectsUnsupportedSchemes() {
        let store = makeStore()
        let fileURL = URL(fileURLWithPath: "/tmp/readme.md")

        let queued = ShareExtensionURLQueueHandler.enqueueURLForLater(fileURL, pendingStore: store)

        XCTAssertNil(queued)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testQueueResultMapperReturnsExpectedMessages() {
        let store = makeStore()
        let item = store.enqueueWebsite(url: "https://example.com")

        XCTAssertTrue(ExtensionQueueResultMapper.queueSucceeded(for: item))
        XCTAssertEqual(
            ExtensionQueueResultMapper.queueMessage(for: item),
            ExtensionUserMessageCatalog.message(for: .savedForLater)
        )
        XCTAssertFalse(ExtensionQueueResultMapper.queueSucceeded(for: nil))
        XCTAssertEqual(
            ExtensionQueueResultMapper.queueMessage(for: nil),
            ExtensionUserMessageCatalog.message(for: .queueFailed)
        )
    }

    private func makeStore() -> PendingShareStore {
        let defaults = UserDefaults(suiteName: suiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directoriesToRemove.append(directory)
        return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
    }
}
