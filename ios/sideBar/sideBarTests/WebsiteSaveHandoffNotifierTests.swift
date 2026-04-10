import XCTest
@testable import sideBarShared

final class WebsiteSaveHandoffNotifierTests: XCTestCase {
    private var suiteName: String!
    private var temporaryDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        suiteName = "WebsiteSaveHandoffNotifierTests.\(UUID().uuidString)"
        temporaryDirectories = []
    }

    override func tearDown() {
        if let suiteName,
           let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        suiteName = nil
        super.tearDown()
    }

    func testNotifierDeliversCallbackAfterWebsiteHandoffPost() {
        assertSingleHandoffDelivery(
            in: self,
            description: "handoff notification received",
            observe: WebsiteSaveHandoffNotifier.observe,
            post: WebsiteSaveHandoffNotifier.post,
            removeObserver: WebsiteSaveHandoffNotifier.removeObserver
        )
    }

    func testPendingShareStoreEnqueueWebsitePostsHandoffNotification() {
        let store = makePendingShareStore()
        assertSingleHandoffDelivery(
            in: self,
            description: "queue handoff notification received",
            observe: WebsiteSaveHandoffNotifier.observe,
            post: {
                _ = store.enqueueWebsite(url: "https://example.com/article")
            },
            removeObserver: WebsiteSaveHandoffNotifier.removeObserver
        )
    }

    func testExtensionEventStoreRecordWebsiteSavedPostsHandoffNotification() {
        let eventStore = makeExtensionEventStore()
        assertSingleHandoffDelivery(
            in: self,
            description: "saved event notification received",
            observe: WebsiteSaveHandoffNotifier.observe,
            post: {
                eventStore.recordWebsiteSaved(url: "https://example.com/article")
            },
            removeObserver: WebsiteSaveHandoffNotifier.removeObserver
        )
    }

    private func makePendingShareStore() -> PendingShareStore {
        let defaults = UserDefaults(suiteName: suiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        temporaryDirectories.append(directory)
        return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
    }

    private func makeExtensionEventStore() -> ExtensionEventStore {
        ExtensionEventStore(userDefaults: UserDefaults(suiteName: suiteName))
    }
}
