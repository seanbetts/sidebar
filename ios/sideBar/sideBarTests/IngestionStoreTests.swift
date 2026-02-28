import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class IngestionStoreTests: XCTestCase {
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
            invalidItem.file.id: LocalUploadRecord(item: invalidItem, bookmarkData: nil),
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

    func testLoadListFiltersTranscriptRowsFromCacheBeforeRefresh() async throws {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        cache.set(
            key: CacheKeys.ingestionList,
            value: IngestionListResponse(
                items: [
                    IngestionStoreTestsSupport.makeItem(id: "keep-cached"),
                    IngestionStoreTestsSupport.makeItem(
                        id: "drop-cached-transcript",
                        filename: "YouTube transcript",
                        sourceMetadata: ["website_transcript": AnyCodable(true)]
                    )
                ]
            ),
            ttlSeconds: 600
        )
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)

        try await store.loadList(force: false)

        XCTAssertEqual(store.items.map(\.file.id), ["keep-cached"])
    }

    func testApplySyncFileInfersRecommendedViewerWhenMissing() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)
        let file = IngestedFileMeta(
            id: "f-sync",
            filenameOriginal: "sync.pdf",
            path: "/sync.pdf",
            mimeOriginal: "application/pdf",
            sizeBytes: 12,
            sha256: nil,
            pinned: true,
            pinnedOrder: 0,
            category: nil,
            sourceUrl: nil,
            sourceMetadata: nil,
            createdAt: "2024-01-01T12:00:00Z",
            updatedAt: "2024-01-01T12:00:00Z",
            deletedAt: nil
        )

        store.applySyncFile(file)

        XCTAssertEqual(store.items.first?.recommendedViewer, "viewer_pdf")
    }

    func testApplyMetaUpdateSwitchesActiveMetaWhenFileIDChangesButShapeMatches() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)
        let first = IngestionStoreTestsSupport.makeMeta(
            fileID: "file-1",
            status: "processing",
            stage: "extracting",
            updatedAt: "2026-01-10T00:00:00Z",
            recommendedViewer: nil
        )
        let second = IngestionStoreTestsSupport.makeMeta(
            fileID: "file-2",
            status: "processing",
            stage: "extracting",
            updatedAt: "2026-01-10T00:00:00Z",
            recommendedViewer: nil
        )

        store.applyMetaUpdate(first, persist: false)
        store.applyMetaUpdate(second, persist: false)

        XCTAssertEqual(store.activeMeta?.file.id, "file-2")
    }

    func testApplyMetaUpdateUpdatesWhenRecommendedViewerChanges() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(api: IngestionStoreTestsSupport.MockIngestionAPI(), cache: cache, userDefaults: defaults)
        let initial = IngestionStoreTestsSupport.makeMeta(
            fileID: "file-1",
            status: "ready",
            stage: "ready",
            updatedAt: "2026-01-10T00:00:00Z",
            recommendedViewer: nil
        )
        let updated = IngestionStoreTestsSupport.makeMeta(
            fileID: "file-1",
            status: "ready",
            stage: "ready",
            updatedAt: "2026-01-10T00:00:00Z",
            recommendedViewer: "text_original"
        )

        store.applyMetaUpdate(initial, persist: false)
        store.applyMetaUpdate(updated, persist: false)

        XCTAssertEqual(store.activeMeta?.recommendedViewer, "text_original")
    }
}
