import Foundation
import XCTest
@testable import sideBarShared
@testable import sideBar

private let pendingShareStoreTestSuiteName = "PendingShareStoreTests"

final class PendingShareStoreTests: XCTestCase {
    private let suiteName = pendingShareStoreTestSuiteName

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

    func testEnqueueWebsiteFailsWhenDefaultsUnavailable() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PendingShareStore(
            baseDirectory: directory,
            userDefaults: nil,
            allowAppGroupFallback: false
        )

        let item = store.enqueueWebsite(url: "https://example.com")

        XCTAssertNil(item)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testCanQueueItemChecksReflectStorageAvailability() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let withStorage = PendingShareStore(
            baseDirectory: directory,
            userDefaults: UserDefaults(suiteName: suiteName)
        )
        let withoutDefaults = PendingShareStore(
            baseDirectory: directory,
            userDefaults: nil,
            allowAppGroupFallback: false
        )

        XCTAssertTrue(withStorage.canQueueURLItems())
        XCTAssertTrue(withStorage.canQueueFileItems())
        XCTAssertFalse(withoutDefaults.canQueueURLItems())
        XCTAssertFalse(withoutDefaults.canQueueFileItems())
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

    func testLoadAllPreservesWebsiteQueueInsertionOrder() {
        let store = makeStore()
        _ = store.enqueueWebsite(url: "https://example.com/first")
        _ = store.enqueueWebsite(url: "https://example.com/second")
        _ = store.enqueueWebsite(url: "https://example.com/third")

        let urls = store.loadAll().compactMap(\.url)
        XCTAssertEqual(
            urls,
            [
                "https://example.com/first",
                "https://example.com/second",
                "https://example.com/third"
            ]
        )
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
            isOffline: { false },
            saveWebsite: { _ in true },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in nil },
            startUpload: { _ in true }
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
            isOffline: { false },
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in nil },
            startUpload: { _ in true }
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
            isOffline: { false },
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in nil },
            startUpload: { _ in true }
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
            isOffline: { false },
            saveWebsite: { _ in false },
            ingestYouTube: { _ in "Failed" },
            resolveFileURL: { _ in nil },
            startUpload: { _ in true }
        )

        XCTAssertTrue(keep)
    }

    func testPendingShareRoutingYouTubeOfflineKeepsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .youtube,
            createdAt: Date(),
            url: "https://www.youtube.com/watch?v=abc123xyzAA"
        )
        var youTubeCalled = false
        let keep = await shouldKeepPendingShareItem(
            item,
            isOffline: { true },
            saveWebsite: { _ in false },
            ingestYouTube: { _ in youTubeCalled = true; return nil },
            resolveFileURL: { _ in nil },
            startUpload: { _ in true }
        )

        XCTAssertTrue(keep)
        XCTAssertFalse(youTubeCalled)
    }

    func testPendingShareRoutingFileMissingPathKeepsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .file,
            createdAt: Date()
        )
        let keep = await shouldKeepPendingShareItem(
            item,
            isOffline: { false },
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in nil },
            startUpload: { _ in true }
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
            isOffline: { false },
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in expectedURL },
            startUpload: { startedUploads.append($0); return true }
        )

        XCTAssertFalse(keep)
        XCTAssertEqual(startedUploads, [expectedURL])
    }

    func testPendingShareRoutingFileOfflineKeepsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .file,
            createdAt: Date(),
            filePath: "pending-shares/\(UUID().uuidString)/file.pdf"
        )
        var uploadCalled = false
        let keep = await shouldKeepPendingShareItem(
            item,
            isOffline: { true },
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in URL(fileURLWithPath: "/tmp/test") },
            startUpload: { _ in uploadCalled = true; return true }
        )

        XCTAssertTrue(keep)
        XCTAssertFalse(uploadCalled)
    }

    func testPendingShareRoutingFileUploadFailureKeepsItem() async {
        let item = PendingShareItem(
            id: UUID(),
            kind: .file,
            createdAt: Date(),
            filePath: "pending-shares/\(UUID().uuidString)/file.pdf"
        )
        let keep = await shouldKeepPendingShareItem(
            item,
            isOffline: { false },
            saveWebsite: { _ in false },
            ingestYouTube: { _ in nil },
            resolveFileURL: { _ in URL(fileURLWithPath: "/tmp/test") },
            startUpload: { _ in false }
        )

        XCTAssertTrue(keep)
    }

}

private func makeStore() -> PendingShareStore {
    let defaults = UserDefaults(suiteName: pendingShareStoreTestSuiteName)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
}
