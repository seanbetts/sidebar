import XCTest
@testable import sideBar

@MainActor
final class IngestionStoreTests: XCTestCase {
    func testApplyIngestedFileEventCachesList() {
        let cache = TestCacheClient()
        let store = IngestionStore(api: MockIngestionAPI(), cache: cache)

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

    func testApplyFileJobEventUpdatesJobStatus() {
        let cache = TestCacheClient()
        let store = IngestionStore(api: MockIngestionAPI(), cache: cache)

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
}

private struct MockIngestionAPI: IngestionProviding {
    func list() async throws -> IngestionListResponse {
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

    func pin(fileId: String, pinned: Bool) async throws {
        _ = fileId
        _ = pinned
        throw MockError.forced
    }

    func delete(fileId: String) async throws {
        _ = fileId
        throw MockError.forced
    }

    func rename(fileId: String, filename: String) async throws {
        _ = fileId
        _ = filename
        throw MockError.forced
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        throw MockError.forced
    }
}

private enum MockError: Error {
    case forced
}
