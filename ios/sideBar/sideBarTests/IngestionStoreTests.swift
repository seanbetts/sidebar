import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class IngestionStoreTests: XCTestCase {
    func testApplyIngestedFileEventCachesList() async {
        let cache = TestCacheClient()
        let defaults = makeDefaults()
        let store = IngestionStore(api: MockIngestionAPI(), cache: cache, userDefaults: defaults)

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

    func testApplyFileJobEventUpdatesJobStatus() async {
        let cache = TestCacheClient()
        let defaults = makeDefaults()
        let store = IngestionStore(api: MockIngestionAPI(), cache: cache, userDefaults: defaults)

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
        let defaults = makeDefaults()
        let store = IngestionStore(api: MockIngestionAPI(), cache: cache, userDefaults: defaults)
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

        let reloaded = IngestionStore(api: MockIngestionAPI(), cache: cache, userDefaults: defaults)
        XCTAssertTrue(reloaded.items.contains { $0.file.id == "local-1" })
    }

    func testApplyIngestedFileEventSkipsWebsiteTranscriptRecords() async {
        let cache = TestCacheClient()
        let defaults = makeDefaults()
        let store = IngestionStore(api: MockIngestionAPI(), cache: cache, userDefaults: defaults)

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
        let defaults = makeDefaults()
        let store = IngestionStore(api: MockIngestionAPI(), cache: cache, userDefaults: defaults)

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
        let defaults = makeDefaults()
        let api = MockIngestionAPI(
            listResponse: IngestionListResponse(
                items: [
                    makeItem(id: "keep-1"),
                    makeItem(
                        id: "drop-transcript",
                        filename: "YouTube transcript",
                        sourceMetadata: ["website_transcript": AnyCodable(true)]
                    ),
                    makeItem(id: "drop-deleted", deletedAt: "2024-01-01T12:01:00Z"),
                    makeItem(id: "drop-ai", path: "/files/drop-ai/ai/ai.md")
                ]
            )
        )
        let store = IngestionStore(api: api, cache: cache, userDefaults: defaults)

        try await store.loadList(force: true)

        XCTAssertEqual(store.items.map(\.file.id), ["keep-1"])
    }

    func testLoadListFiltersTranscriptRowsFromCacheBeforeRefresh() async throws {
        let cache = TestCacheClient()
        let defaults = makeDefaults()
        cache.set(
            key: CacheKeys.ingestionList,
            value: IngestionListResponse(
                items: [
                    makeItem(id: "keep-cached"),
                    makeItem(
                        id: "drop-cached-transcript",
                        filename: "YouTube transcript",
                        sourceMetadata: ["website_transcript": AnyCodable(true)]
                    )
                ]
            ),
            ttlSeconds: 600
        )
        let store = IngestionStore(api: MockIngestionAPI(), cache: cache, userDefaults: defaults)

        try await store.loadList(force: false)

        XCTAssertEqual(store.items.map(\.file.id), ["keep-cached"])
    }
}

private struct MockIngestionAPI: IngestionProviding {
    let listResponse: IngestionListResponse?

    init(listResponse: IngestionListResponse? = nil) {
        self.listResponse = listResponse
    }

    func list() async throws -> IngestionListResponse {
        if let listResponse {
            return listResponse
        }
        throw MockError.forced
    }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        _ = fileId
        throw MockError.forced
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = fileId
        _ = kind
        _ = range
        throw MockError.forced
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
        throw MockError.forced
    }

    func delete(fileId: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = clientUpdatedAt
        throw MockError.forced
    }

    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = filename
        _ = clientUpdatedAt
        throw MockError.forced
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        throw MockError.forced
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        throw MockError.forced
    }
}

private func makeDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "IngestionStoreTests") ?? .standard
    defaults.removePersistentDomain(forName: "IngestionStoreTests")
    return defaults
}

private enum MockError: Error {
    case forced
}

private func makeItem(
    id: String,
    filename: String = "doc.txt",
    path: String = "/doc.txt",
    sourceMetadata: [String: AnyCodable]? = nil,
    deletedAt: String? = nil
) -> IngestionListItem {
    IngestionListItem(
        file: IngestedFileMeta(
            id: id,
            filenameOriginal: filename,
            path: path,
            mimeOriginal: "text/plain",
            sizeBytes: 12,
            sha256: nil,
            pinned: nil,
            pinnedOrder: nil,
            category: nil,
            sourceUrl: nil,
            sourceMetadata: sourceMetadata,
            createdAt: "2024-01-01T12:00:00Z",
            updatedAt: "2024-01-01T12:00:00Z",
            deletedAt: deletedAt
        ),
        job: IngestionJob(
            status: "processing",
            stage: "extracting",
            errorCode: nil,
            errorMessage: nil,
            userMessage: nil,
            progress: nil,
            attempts: 0,
            updatedAt: "2024-01-01T12:00:00Z"
        ),
        recommendedViewer: nil
    )
}
