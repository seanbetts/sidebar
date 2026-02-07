import Foundation
import XCTest
@testable import sideBarShared
@testable import sideBar

final class PendingShareStoreTests: XCTestCase {
    private let suiteName = "PendingShareStoreTests"

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    func testEnqueueWebsiteStoresItem() {
        let store = makeStore()

        let item = store.enqueueWebsite(url: "https://example.com")

        XCTAssertNotNil(item)
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.url, "https://example.com")
    }

    func testEnqueueWebsiteDeduplicates() {
        let store = makeStore()

        let first = store.enqueueWebsite(url: "https://example.com")
        let second = store.enqueueWebsite(url: "https://example.com")

        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(store.loadAll().count, 1)
    }

    func testEnqueueYouTubeStoresItem() {
        let store = makeStore()

        let item = store.enqueueYouTube(url: "https://youtube.com/watch?v=abc123")

        XCTAssertNotNil(item)
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.first?.kind, .youtube)
    }

    func testEnqueueYouTubeDeduplicates() {
        let store = makeStore()

        let first = store.enqueueYouTube(url: "https://youtube.com/watch?v=abc123")
        let second = store.enqueueYouTube(url: "https://youtube.com/watch?v=abc123")

        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(store.loadAll().count, 1)
    }

    func testEnqueueFileWritesData() throws {
        let store = makeStore()
        let payload = Data("hello".utf8)

        let item = store.enqueueFile(
            data: payload,
            filename: "sample.txt",
            mimeType: "text/plain",
            kind: .file
        )

        let resolved = item.flatMap { store.resolveFileURL(for: $0) }
        XCTAssertNotNil(resolved)
        let storedData = try resolved.map { try Data(contentsOf: $0) }
        XCTAssertEqual(storedData, payload)
    }

    func testRemoveDeletesItem() {
        let store = makeStore()
        let first = store.enqueueWebsite(url: "https://example.com")
        let second = store.enqueueWebsite(url: "https://example.org")

        store.remove(ids: [first?.id].compactMap { $0 })

        let remaining = store.loadAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.url, second?.url)
    }

    func testConsumeAllClearsItems() {
        let store = makeStore()
        _ = store.enqueueWebsite(url: "https://example.com")
        _ = store.enqueueYouTube(url: "https://youtube.com/watch?v=abc123")

        let consumed = store.consumeAll()

        XCTAssertEqual(consumed.count, 2)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testPendingShareRoutingWebsiteSuccessDropsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: Date(),
            url: "https://example.com"
        )
        let keep = await shouldKeepPendingShareItem(
            item,
            saveWebsite: { _ in true },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in nil },
            startUpload: { _ in }
        )

        XCTAssertFalse(keep)
    }

    func testPendingShareRoutingWebsiteFailureKeepsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: Date(),
            url: "https://example.com"
        )
        let keep = await shouldKeepPendingShareItem(
            item,
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in nil },
            startUpload: { _ in }
        )

        XCTAssertTrue(keep)
    }

    func testPendingShareRoutingLegacyYouTubeSuccessDropsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .youtube,
            createdAt: Date(),
            url: "https://www.youtube.com/watch?v=abc123xyzAA"
        )
        let keep = await shouldKeepPendingShareItem(
            item,
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in nil },
            startUpload: { _ in }
        )

        XCTAssertFalse(keep)
    }

    func testPendingShareRoutingLegacyYouTubeFailureKeepsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .youtube,
            createdAt: Date(),
            url: "https://www.youtube.com/watch?v=abc123xyzAA"
        )
        let keep = await shouldKeepPendingShareItem(
            item,
            saveWebsite: { _ in false },
            ingestYouTube: { _ in "Failed" },
            resolveFileURL: { _ in nil },
            startUpload: { _ in }
        )

        XCTAssertTrue(keep)
    }

    func testPendingShareRoutingFileMissingPathKeepsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .file,
            createdAt: Date()
        )
        let keep = await shouldKeepPendingShareItem(
            item,
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in nil },
            startUpload: { _ in }
        )

        XCTAssertTrue(keep)
    }

    func testPendingShareRoutingFileResolvedStartsUploadAndDropsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .file,
            createdAt: Date(),
            filePath: "pending-shares/\(UUID().uuidString)/file.pdf"
        )
        let expectedURL = URL(fileURLWithPath: "/tmp/test-upload")
        var startedUploads: [URL] = []

        let keep = await shouldKeepPendingShareItem(
            item,
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in expectedURL },
            startUpload: { startedUploads.append($0) }
        )

        XCTAssertFalse(keep)
        XCTAssertEqual(startedUploads, [expectedURL])
    }

    func testExtensionURLMessageHandlerRejectsUnsupportedAction() {
        let store = makeStore()
        let response = ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "other_action",
            urlString: "https://example.com",
            pendingStore: store
        )

        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "Unsupported action")
    }

    func testExtensionURLMessageHandlerRejectsMissingURL() {
        let store = makeStore()
        let response = ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: nil,
            pendingStore: store
        )

        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "Missing URL")
    }

    func testExtensionURLMessageHandlerQueuesWebsiteForYouTubeURL() {
        let store = makeStore()
        let response = ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: "https://www.youtube.com/watch?v=abc123xyzAA",
            pendingStore: store
        )

        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["queued"] as? String, "website")
        XCTAssertEqual(store.loadAll().first?.kind, .website)
    }

    func testShareExtensionURLQueueHandlerQueuesWebsiteForYouTubeURL() {
        let store = makeStore()
        let url = URL(string: "https://www.youtube.com/watch?v=abc123xyzAA")!

        let item = ShareExtensionURLQueueHandler.enqueueURLForLater(url, pendingStore: store)

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.kind, .website)
        XCTAssertEqual(store.loadAll().first?.kind, .website)
    }

    private func makeStore() -> PendingShareStore {
        let defaults = UserDefaults(suiteName: suiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
    }
}
