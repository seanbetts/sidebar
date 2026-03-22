import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class IngestionStoreTests: XCTestCase {
    private func makeWidgetDataManager() -> WidgetDataManager {
        WidgetDataManager(
            userDefaults: UserDefaults(
                suiteName: "IngestionStoreTests.widget.\(UUID().uuidString)"
            )!
        )
    }

    func testApplyIngestedFileEventCachesList() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)

        let payload = RealtimePayload<IngestedFileRealtimeRecord>(
            eventType: .insert,
            table: RealtimeTable.ingestedFiles,
            schema: "public",
            record: IngestedFileRealtimeRecord(
                id: "f1",
                filenameOriginal: "doc.txt",
                path: "/doc.txt",
                mimeOriginal: "text/plain",
                sizeBytes: 12,
                sha256: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                pinned: nil,
                pinnedOrder: nil,
                createdAt: "2024-01-01T12:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )

        store.applyIngestedFileEvent(payload)

        XCTAssertEqual(store.items.count, 1)
        let cached: IngestionListResponse? = cache.get(key: CacheKeys.ingestionList)
        XCTAssertEqual(cached?.items.first?.file.id, "f1")
    }

    func testApplyIngestedFileEventPreservesRecommendedViewerForExistingFile() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)
        let existing = IngestionStoreTestsSupport.makeItem(
            id: "f1",
            mimeOriginal: "application/pdf",
            pinned: true,
            status: "ready",
            stage: "ready",
            recommendedViewer: "viewer_pdf"
        )
        store.applyListUpdate([existing], persist: false)

        let payload = RealtimePayload<IngestedFileRealtimeRecord>(
            eventType: .update,
            table: RealtimeTable.ingestedFiles,
            schema: "public",
            record: IngestedFileRealtimeRecord(
                id: "f1",
                filenameOriginal: "doc-v2.pdf",
                path: "/doc-v2.pdf",
                mimeOriginal: "application/pdf",
                sizeBytes: 20,
                sha256: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                pinned: true,
                pinnedOrder: 0,
                createdAt: "2024-01-01T12:00:00Z",
                updatedAt: "2024-01-01T12:01:00Z",
                deletedAt: nil
            ),
            oldRecord: nil
        )

        store.applyIngestedFileEvent(payload)

        XCTAssertEqual(store.items.first?.recommendedViewer, "viewer_pdf")
        XCTAssertEqual(store.items.first?.file.pinned, true)
    }

    func testApplyFileJobEventUpdatesJobStatus() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)

        let insert = RealtimePayload<IngestedFileRealtimeRecord>(
            eventType: .insert,
            table: RealtimeTable.ingestedFiles,
            schema: "public",
            record: IngestedFileRealtimeRecord(
                id: "f1",
                filenameOriginal: "doc.txt",
                path: "/doc.txt",
                mimeOriginal: "text/plain",
                sizeBytes: 12,
                sha256: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                pinned: nil,
                pinnedOrder: nil,
                createdAt: "2024-01-01T12:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )
        store.applyIngestedFileEvent(insert)

        let jobPayload = RealtimePayload<FileJobRealtimeRecord>(
            eventType: .update,
            table: RealtimeTable.fileJobs,
            schema: "public",
            record: FileJobRealtimeRecord(
                fileId: "f1",
                status: "failed",
                stage: "extract",
                errorCode: "E1",
                errorMessage: "Nope",
                attempts: 2,
                updatedAt: "2024-01-01T12:00:00Z"
            ),
            oldRecord: nil
        )

        store.applyFileJobEvent(jobPayload)

        XCTAssertEqual(store.items.first?.job.status, "failed")
        let cached: IngestionListResponse? = cache.get(key: CacheKeys.ingestionList)
        XCTAssertEqual(cached?.items.first?.job.status, "failed")
    }

    func testLocalUploadsPersistAndReload() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)
        let item = IngestionListItem(
            file: IngestedFileMeta(
                id: "local-1",
                filenameOriginal: "doc.txt",
                path: nil,
                mimeOriginal: "text/plain",
                sizeBytes: 10,
                sha256: nil,
                pinned: false,
                pinnedOrder: nil,
                category: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "uploading",
                stage: "uploading",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: 0,
                attempts: 0,
                updatedAt: nil
            ),
            recommendedViewer: nil
        )

        store.addLocalUpload(item)

        let reloaded = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)
        XCTAssertTrue(reloaded.items.contains { $0.file.id == "local-1" })
    }

    func testLoadLocalUploadsDropsInvalidIdentifiers() async throws {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let validItem = IngestionStoreTestsSupport.makeItem(id: "local-1", status: "uploading", stage: "uploading")
        let invalidItem = IngestionStoreTestsSupport.makeItem(id: "file-1", status: "processing", stage: "extracting")
        let payload: [String: LocalUploadRecord] = [
            validItem.file.id: LocalUploadRecord(item: validItem, bookmarkData: nil),
            invalidItem.file.id: LocalUploadRecord(item: invalidItem, bookmarkData: nil)
        ]
        defaults.set(try JSONEncoder().encode(payload), forKey: "ingestion.localUploads")

        let reloaded = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            userDefaults: defaults
        )

        XCTAssertTrue(reloaded.items.contains { $0.file.id == "local-1" })
        XCTAssertFalse(reloaded.items.contains { $0.file.id == "file-1" })
    }

    func testApplyListUpdateRepairsFileWidgetSnapshotEvenWhenListIsUnchanged() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let widgetDataManager = makeWidgetDataManager()
        let store = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            widgetDataManager: widgetDataManager,
            userDefaults: defaults
        )
        let item = IngestionStoreTestsSupport.makeItem(
            id: "file-1",
            filename: "Pinned.pdf",
            mimeOriginal: "application/pdf",
            pinned: true,
            pinnedOrder: 0,
            status: "ready",
            stage: "ready",
            recommendedViewer: "viewer_pdf"
        )

        store.applyListUpdate([item], persist: false)
        widgetDataManager.store(WidgetFileData.empty, for: .files)

        store.applyListUpdate([item], persist: false)

        let snapshot: WidgetFileData = widgetDataManager.load(for: .files)
        XCTAssertEqual(snapshot.totalCount, 1)
        XCTAssertEqual(snapshot.files.map(\.id), ["file-1"])
    }

    func testApplyPinnedOrderReordersPinnedFiles() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let widgetDataManager = makeWidgetDataManager()
        let store = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            widgetDataManager: widgetDataManager,
            userDefaults: defaults
        )
        let first = IngestionStoreTestsSupport.makeItem(
            id: "file-a",
            filename: "A.pdf",
            pinned: true,
            pinnedOrder: 0,
            status: "ready",
            stage: "ready"
        )
        let second = IngestionStoreTestsSupport.makeItem(
            id: "file-b",
            filename: "B.pdf",
            pinned: true,
            pinnedOrder: 1,
            status: "ready",
            stage: "ready"
        )
        let unpinned = IngestionStoreTestsSupport.makeItem(
            id: "file-c",
            filename: "C.pdf",
            pinned: false,
            status: "ready",
            stage: "ready"
        )
        store.applyListUpdate([first, second, unpinned], persist: false)

        store.applyPinnedOrder(["file-b", "file-a"])

        XCTAssertEqual(store.pinnedFileOrder(), ["file-b", "file-a"])
        XCTAssertEqual(
            store.items
                .filter { $0.file.pinned == true }
                .sorted { ($0.file.pinnedOrder ?? Int.max) < ($1.file.pinnedOrder ?? Int.max) }
                .map(\.file.id),
            ["file-b", "file-a"]
        )
    }

    func testApplyPinnedOrderRestoresWidgetSnapshotWhenPreviousOrderIsReapplied() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let widgetDataManager = makeWidgetDataManager()
        let store = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            widgetDataManager: widgetDataManager,
            userDefaults: defaults
        )
        let first = IngestionStoreTestsSupport.makeItem(
            id: "file-a",
            filename: "A.pdf",
            pinned: true,
            pinnedOrder: 0,
            status: "ready",
            stage: "ready"
        )
        let second = IngestionStoreTestsSupport.makeItem(
            id: "file-b",
            filename: "B.pdf",
            pinned: true,
            pinnedOrder: 1,
            status: "ready",
            stage: "ready"
        )
        store.applyListUpdate([first, second], persist: false)

        let previousOrder = store.pinnedFileOrder()

        store.applyPinnedOrder(["file-b", "file-a"])
        store.applyPinnedOrder(previousOrder)

        let snapshot: WidgetFileData = widgetDataManager.load(for: .files)
        XCTAssertEqual(snapshot.files.map(\.id), ["file-a", "file-b"])
        XCTAssertEqual(snapshot.totalCount, 2)
    }

    func testApplyIngestedFileEventSkipsWebsiteTranscriptRecords() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)

        let payload = RealtimePayload<IngestedFileRealtimeRecord>(
            eventType: .insert,
            table: RealtimeTable.ingestedFiles,
            schema: "public",
            record: IngestedFileRealtimeRecord(
                id: "f-transcript",
                filenameOriginal: "YouTube transcript",
                path: "/YouTube transcript",
                mimeOriginal: "video/youtube",
                sizeBytes: 0,
                sha256: nil,
                sourceUrl: "https://www.youtube.com/watch?v=abc123xyz89",
                sourceMetadata: ["website_transcript": AnyCodable(true)],
                pinned: nil,
                pinnedOrder: nil,
                createdAt: "2024-01-01T12:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )

        store.applyIngestedFileEvent(payload)

        XCTAssertTrue(store.items.isEmpty)
        let cached: IngestionListResponse? = cache.get(key: CacheKeys.ingestionList)
        XCTAssertTrue(cached?.items.isEmpty ?? true)
    }

    func testApplyIngestedFileEventUpdateRemovesSoftDeletedRecord() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)

        let insertPayload = RealtimePayload<IngestedFileRealtimeRecord>(
            eventType: .insert,
            table: RealtimeTable.ingestedFiles,
            schema: "public",
            record: IngestedFileRealtimeRecord(
                id: "f1",
                filenameOriginal: "doc.txt",
                path: "/doc.txt",
                mimeOriginal: "text/plain",
                sizeBytes: 12,
                sha256: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                pinned: nil,
                pinnedOrder: nil,
                createdAt: "2024-01-01T12:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            oldRecord: nil
        )
        store.applyIngestedFileEvent(insertPayload)
        XCTAssertEqual(store.items.count, 1)

        let updatePayload = RealtimePayload<IngestedFileRealtimeRecord>(
            eventType: .update,
            table: RealtimeTable.ingestedFiles,
            schema: "public",
            record: IngestedFileRealtimeRecord(
                id: "f1",
                filenameOriginal: "doc.txt",
                path: "/doc.txt",
                mimeOriginal: "text/plain",
                sizeBytes: 12,
                sha256: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                pinned: nil,
                pinnedOrder: nil,
                createdAt: "2024-01-01T12:00:00Z",
                updatedAt: "2024-01-01T12:01:00Z",
                deletedAt: "2024-01-01T12:01:00Z"
            ),
            oldRecord: nil
        )

        store.applyIngestedFileEvent(updatePayload)

        XCTAssertTrue(store.items.isEmpty)
        let cached: IngestionListResponse? = cache.get(key: CacheKeys.ingestionList)
        XCTAssertTrue(cached?.items.isEmpty ?? true)
    }

    func testLoadListFiltersTranscriptAndDeletedRowsFromAPI() async throws {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let api = IngestionStoreTestsSupport.MockIngestionAPI(
            listResponse: IngestionListResponse(
                items: [
                    IngestionStoreTestsSupport.makeItem(id: "keep-1"),
                    IngestionStoreTestsSupport.makeItem(
                        id: "drop-transcript",
                        filename: "YouTube transcript",
                        sourceMetadata: ["website_transcript": AnyCodable(true)]
                    ),
                    IngestionStoreTestsSupport.makeItem(id: "drop-deleted", deletedAt: "2024-01-01T12:01:00Z"),
                    IngestionStoreTestsSupport.makeItem(id: "drop-ai", path: "/files/drop-ai/ai/ai.md")
                ]
            )
        )
        let store = IngestionStore(api: api, cache: cache, userDefaults: defaults)

        try await store.loadList(force: true)

        XCTAssertEqual(store.items.map(\.file.id), ["keep-1"])
    }

}
