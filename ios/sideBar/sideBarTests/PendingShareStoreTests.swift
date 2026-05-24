import Foundation
import XCTest
@testable import sideBarShared
@testable import sideBar

private let pendingShareStoreTestSuiteName = "PendingShareStoreTests"

@MainActor
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
    func testResolveFileURLRejectsAbsoluteAndTraversalPaths() throws {
        let store = makeStore()
        let absolute = PendingShareItem(
            id: UUID(), kind: .file,
            createdAt: Date(),
            filePath: "/tmp/escaped.txt",
            filename: "escaped.txt", mimeType: "text/plain"
        )
        let traversal = PendingShareItem(
            id: UUID(), kind: .file,
            createdAt: Date(),
            filePath: "pending-shares/\(UUID().uuidString)/../escaped.txt",
            filename: "escaped.txt", mimeType: "text/plain"
        )

        XCTAssertNil(store.resolveFileURL(for: absolute))
        XCTAssertNil(store.resolveFileURL(for: traversal))
    }
    func testRemoveDeletesStagedFileAndContainingDirectory() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8),
            filename: "sample.txt",
            mimeType: "text/plain",
            kind: .file
        ))
        let fileURL = try XCTUnwrap(store.resolveFileURL(for: item))
        let itemDirectory = fileURL.deletingLastPathComponent()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemDirectory.path))

        store.remove(ids: [item.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemDirectory.path))
        XCTAssertTrue(store.loadAll().isEmpty)
    }
    func testRemoveDoesNotDeleteOutsidePendingShareRootForInvalidPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("outside.txt")
        try Data("do not delete".utf8).write(to: outside)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "\(suiteName).\(UUID().uuidString)"))
        let store = PendingShareStore(
            baseDirectory: directory,
            userDefaults: defaults,
            allowAppGroupFallback: false
        )
        let item = PendingShareItem(
            id: UUID(), kind: .file,
            createdAt: Date(),
            filePath: "../outside.txt",
            filename: "outside.txt", mimeType: "text/plain"
        )

        store.replaceAll([item])
        store.remove(ids: [item.id])

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(store.loadAll().isEmpty)
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
    func testClearAllClearsItemsAndDeletesStagedFiles() throws {
        let store = makeStore()
        let payload = Data("hello".utf8)
        let fileItem = store.enqueueFile(
            data: payload,
            filename: "sample.txt",
            mimeType: "text/plain",
            kind: .file
        )
        _ = store.enqueueWebsite(url: "https://example.com")
        let stagedFileURL = fileItem.flatMap { store.resolveFileURL(for: $0) }
        XCTAssertNotNil(stagedFileURL)
        if let stagedFileURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: stagedFileURL.path))
        }
        store.clearAll()
        XCTAssertTrue(store.loadAll().isEmpty)
        if let stagedFileURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagedFileURL.path))
        }
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
extension PendingShareStoreTests {
    func testPendingWebsiteFailureKindClassifiesValidationErrorsAsTerminal() {
        XCTAssertEqual(pendingWebsiteFailureKind(for: "Enter a valid URL."), .terminal)
        XCTAssertEqual(
            pendingWebsiteFailureKind(for: "Request failed (HTTP 400)."),
            .terminal
        )
        XCTAssertEqual(
            pendingWebsiteFailureKind(for: "Request failed (HTTP 422)."),
            .terminal
        )
    }
    func testPendingWebsiteFailureKindClassifiesNetworkAndServerErrorsAsRetryable() {
        XCTAssertEqual(
            pendingWebsiteFailureKind(for: "Network connection failed. Please check your internet."),
            .retryable
        )
        XCTAssertEqual(
            pendingWebsiteFailureKind(for: "Request failed (HTTP 503)."),
            .retryable
        )
    }
    func testNextPendingWebsiteRetryItemSchedulesBackoffAndIncrementsCount() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let item = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: now,
            url: "https://example.com",
            retryCount: 1
        )
        let retry = nextPendingWebsiteRetryItem(
            from: item,
            now: now,
            errorMessage: "Server error. Please try again soon."
        )
        XCTAssertNotNil(retry)
        XCTAssertEqual(retry?.retryCount, 2)
        XCTAssertEqual(retry?.lastError, "Server error. Please try again soon.")
        XCTAssertEqual(retry?.nextRetryAt, now.addingTimeInterval(60))
    }
    func testNextPendingWebsiteRetryItemDropsOnTerminalOrRetryLimit() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let terminal = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: now,
            url: "https://example.com"
        )
        let capped = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: now,
            url: "https://example.com",
            retryCount: 4
        )
        XCTAssertNil(
            nextPendingWebsiteRetryItem(
                from: terminal,
                now: now,
                errorMessage: "Enter a valid URL."
            )
        )
        XCTAssertNil(
            nextPendingWebsiteRetryItem(
                from: capped,
                now: now,
                errorMessage: "Server error. Please try again soon."
            )
        )
    }
    func testFailedPendingWebsiteItemMarksQueueEntryAsManualRetryOnly() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let item = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: now,
            url: "https://example.com",
            retryCount: 2,
            nextRetryAt: now.addingTimeInterval(30)
        )
        let failed = failedPendingWebsiteItem(
            from: item,
            errorMessage: "Request failed (HTTP 503)."
        )
        XCTAssertEqual(failed.retryCount, pendingWebsiteQueueMaxRetryCount)
        XCTAssertNil(failed.nextRetryAt)
        XCTAssertEqual(failed.lastError, "Request failed (HTTP 503).")
        XCTAssertTrue(isPendingWebsiteFailed(failed))
    }
    func testIsPendingWebsiteFailedRequiresRetryLimitWithoutScheduledRetry() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let failed = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: now,
            url: "https://example.com",
            retryCount: pendingWebsiteQueueMaxRetryCount,
            nextRetryAt: nil
        )
        let retrying = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: now,
            url: "https://example.com",
            retryCount: pendingWebsiteQueueMaxRetryCount,
            nextRetryAt: now.addingTimeInterval(30)
        )
        XCTAssertTrue(isPendingWebsiteFailed(failed))
        XCTAssertFalse(isPendingWebsiteFailed(retrying))
    }
    func testIsPendingWebsiteReadyForRetryHonorsNextRetryAt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ready = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: now,
            url: "https://example.com",
            nextRetryAt: now.addingTimeInterval(-1)
        )
        let waiting = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: now,
            url: "https://example.com",
            nextRetryAt: now.addingTimeInterval(120)
        )
        XCTAssertTrue(isPendingWebsiteReadyForRetry(ready, now: now))
        XCTAssertFalse(isPendingWebsiteReadyForRetry(waiting, now: now))
    }
}

private func makeStore() -> PendingShareStore {
    let defaults = UserDefaults(suiteName: pendingShareStoreTestSuiteName)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
}
