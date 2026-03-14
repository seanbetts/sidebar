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
        let expectation = expectation(description: "handoff notification received")
        let observer = WebsiteSaveHandoffNotifier.observe {
            expectation.fulfill()
        }

        WebsiteSaveHandoffNotifier.post()

        wait(for: [expectation], timeout: 1.0)
        WebsiteSaveHandoffNotifier.removeObserver(observer)
    }

    func testPendingShareStoreEnqueueWebsitePostsHandoffNotification() {
        let store = makePendingShareStore()
        let expectation = expectation(description: "queue handoff notification received")
        let observer = WebsiteSaveHandoffNotifier.observe {
            expectation.fulfill()
        }

        _ = store.enqueueWebsite(url: "https://example.com/article")

        wait(for: [expectation], timeout: 1.0)
        WebsiteSaveHandoffNotifier.removeObserver(observer)
    }

    func testExtensionEventStoreRecordWebsiteSavedPostsHandoffNotification() {
        let eventStore = makeExtensionEventStore()
        let website = ExtensionSavedWebsite(
            id: "website-\(UUID().uuidString)",
            title: "Saved Website",
            url: "https://example.com/article",
            urlFull: "https://example.com/article",
            domain: "example.com",
            content: "Saved content",
            source: "web",
            savedAt: "2026-03-14T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: nil,
            lastOpenedAt: nil
        )
        let expectation = expectation(description: "saved event notification received")
        let observer = WebsiteSaveHandoffNotifier.observe {
            expectation.fulfill()
        }

        eventStore.recordWebsiteSaved(website: website)

        wait(for: [expectation], timeout: 1.0)
        WebsiteSaveHandoffNotifier.removeObserver(observer)
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
