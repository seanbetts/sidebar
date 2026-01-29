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
                createdAt: "2026-01-01T00:00:00Z"
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

private func makeDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "IngestionStoreTests") ?? .standard
    defaults.removePersistentDomain(forName: "IngestionStoreTests")
    return defaults
}

private enum MockError: Error {
    case forced
}
