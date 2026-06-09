import Foundation
import XCTest
@testable import sideBarShared
@testable import sideBar

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
    func testEnqueueWebsiteDirectSavePersistsSelectionIntent() {
        let store = makeStore()
        let item = store.enqueueWebsite(url: "https://example.com", selectAfterSave: true)

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.selectAfterSave, true)
        XCTAssertEqual(store.loadAll().first?.selectAfterSave, true)
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
    func testEnqueueYouTubeUsesInjectedIDGenerator() throws {
        let expectedId = UUID(uuidString: "F6AB0DE5-F941-480D-9262-1D996F5A36D9")!
        let (store, _) = try makeIsolatedStore(idGenerator: { expectedId })
        let item = store.enqueueYouTube(url: "https://youtube.com/watch?v=abc123")
        XCTAssertEqual(item?.id, expectedId)
        XCTAssertEqual(store.loadAll().first?.id, expectedId)
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
    func testClearAllPreservesUnrelatedPendingShareRootContent() throws {
        let (store, directory) = try makeIsolatedStore()
        let root = directory.appendingPathComponent("pending-shares", isDirectory: true)
        let unrelated = root.appendingPathComponent("manual/keep.txt")
        try FileManager.default.createDirectory(at: unrelated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: unrelated)
        let item = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8), filename: "sample.txt", mimeType: "text/plain", kind: .file
        ))
        let fileURL = try XCTUnwrap(store.resolveFileURL(for: item))

        store.clearAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(store.loadAll().isEmpty)
    }
    func testCleanupPreservesUnrelatedAndNonEmptyPendingShareDirectories() throws {
        let (store, directory) = try makeIsolatedStore()
        let root = directory.appendingPathComponent("pending-shares", isDirectory: true)
        let manual = root.appendingPathComponent("manual")
        let nonEmptyUUID = root.appendingPathComponent(UUID().uuidString)
        let symlink = root.appendingPathComponent(UUID().uuidString)
        let symlinkTarget = directory.appendingPathComponent("symlink-target")
        try FileManager.default.createDirectory(at: manual, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nonEmptyUUID, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symlinkTarget, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: symlinkTarget)
        try Data("keep".utf8).write(to: nonEmptyUUID.appendingPathComponent("keep.txt"))
        let emptyUUID = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: emptyUUID, withIntermediateDirectories: true)
        let oldDate = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.creationDate: oldDate], ofItemAtPath: emptyUUID.path)

        store.cleanup(olderThan: 1)

        XCTAssertTrue(FileManager.default.fileExists(atPath: manual.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonEmptyUUID.path))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: symlink.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyUUID.path))
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
        let item = pendingWebsiteItem()
        let keep = await routePendingShareItem(item, saveWebsite: { _ in true })
        XCTAssertFalse(keep)
    }
    func testPendingShareRoutingWebsiteFailureKeepsItem() async {
        let item = pendingWebsiteItem()
        let keep = await routePendingShareItem(item)
        XCTAssertTrue(keep)
    }
    func testPendingShareRoutingLegacyYouTubeSuccessDropsItem() async {
        let item = pendingYouTubeItem()
        let keep = await routePendingShareItem(item)
        XCTAssertFalse(keep)
    }
    func testPendingShareRoutingLegacyYouTubeFailureKeepsItem() async {
        let item = pendingYouTubeItem()
        let keep = await routePendingShareItem(item, ingestYouTube: { _ in "Failed" })
        XCTAssertTrue(keep)
    }
    func testPendingShareRoutingYouTubeOfflineKeepsItem() async {
        let item = pendingYouTubeItem()
        var youTubeCalled = false
        let keep = await routePendingShareItem(
            item, isOffline: { true }, ingestYouTube: { _ in youTubeCalled = true; return nil }
        )
        XCTAssertTrue(keep)
        XCTAssertFalse(youTubeCalled)
    }
    func testPendingShareRoutingFileMissingPathKeepsItem() async {
        let item = PendingShareItem(id: UUID(), kind: .file, createdAt: Date())
        let keep = await routePendingShareItem(item)
        XCTAssertTrue(keep)
    }
    func testPendingShareRoutingFileResolvedStartsUploadAndDropsItem() async {
        let item = pendingFileItem()
        let expectedURL = URL(fileURLWithPath: "/tmp/test-upload")
        var startedUploads: [URL] = []
        let keep = await routePendingShareItem(
            item, prepareFileForUpload: { _ in expectedURL }, startUpload: { startedUploads.append($0); return true }
        )
        XCTAssertFalse(keep)
        XCTAssertEqual(startedUploads, [expectedURL])
    }
    func testPendingShareRoutingFileOfflineKeepsItem() async {
        let item = pendingFileItem()
        var uploadCalled = false
        let keep = await routePendingShareItem(
            item,
            isOffline: { true },
            prepareFileForUpload: { _ in URL(fileURLWithPath: "/tmp/test") },
            startUpload: { _ in uploadCalled = true; return true }
        )
        XCTAssertTrue(keep)
        XCTAssertFalse(uploadCalled)
    }
    func testPendingShareRoutingFileUploadFailureKeepsItem() async {
        let item = pendingFileItem()
        let keep = await routePendingShareItem(item, prepareFileForUpload: { _ in URL(fileURLWithPath: "/tmp/test") })
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
        let item = pendingWebsiteItem(createdAt: now, retryCount: 1)
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
        let terminal = pendingWebsiteItem(createdAt: now)
        let capped = pendingWebsiteItem(createdAt: now, retryCount: 4)
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
        let item = pendingWebsiteItem(
            createdAt: now, retryCount: 2, nextRetryAt: now.addingTimeInterval(30)
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
        let failed = pendingWebsiteItem(createdAt: now, retryCount: pendingWebsiteQueueMaxRetryCount)
        let retrying = pendingWebsiteItem(
            createdAt: now,
            retryCount: pendingWebsiteQueueMaxRetryCount,
            nextRetryAt: now.addingTimeInterval(30)
        )
        XCTAssertTrue(isPendingWebsiteFailed(failed))
        XCTAssertFalse(isPendingWebsiteFailed(retrying))
    }
    func testIsPendingWebsiteReadyForRetryHonorsNextRetryAt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ready = pendingWebsiteItem(createdAt: now, nextRetryAt: now.addingTimeInterval(-1))
        let waiting = pendingWebsiteItem(createdAt: now, nextRetryAt: now.addingTimeInterval(120))
        XCTAssertTrue(isPendingWebsiteReadyForRetry(ready, now: now))
        XCTAssertFalse(isPendingWebsiteReadyForRetry(waiting, now: now))
    }
}
