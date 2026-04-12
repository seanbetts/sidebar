import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WebsitesWriteQueueExecutorTests: XCTestCase {
    func testExecuteAppliesSyncResponseInSingleBatch() async throws {
        let api = WebsitesWriteQueueExecutorAPIStub()
        let store = WebsitesWriteQueueStoreSpy()
        let executor = WebsitesWriteQueueExecutor(api: api, store: store)

        try await executor.execute(write: makeWrite(operationId: "op-1", websiteId: "website-1"))

        XCTAssertEqual(store.batchApplyCallCount, 1)
        XCTAssertEqual(store.individualApplyCallCount, 0)
        XCTAssertEqual(store.appliedBatchIDs, [["website-1", "website-2", "website-3"]])
    }

    private func makeWrite(operationId: String, websiteId: String) throws -> PendingWriteRecord {
        let payload = WebsiteOperationPayload(
            operationId: operationId,
            op: "rename",
            id: websiteId,
            title: "Updated title"
        )
        let encoded = try JSONEncoder().encode(payload)
        return PendingWriteRecord(
            id: UUID(),
            operationType: WriteOperation.rename.rawValue,
            entityType: WriteEntityType.website.rawValue,
            entityId: websiteId,
            payload: encoded,
            serverSnapshot: nil,
            attempts: 0
        )
    }
}

@MainActor
private final class WebsitesWriteQueueStoreSpy: WebsitesWriteQueueApplying {
    private(set) var batchApplyCallCount = 0
    private(set) var individualApplyCallCount = 0
    private(set) var appliedBatchIDs: [[String]] = []

    func applySyncItem(_ item: WebsiteItem) {
        individualApplyCallCount += 1
        appliedBatchIDs.append([item.id])
    }

    func applySyncItems(_ items: [WebsiteItem]) {
        batchApplyCallCount += 1
        appliedBatchIDs.append(items.map(\.id))
    }
}

private final class WebsitesWriteQueueExecutorAPIStub: WebsitesProviding {
    func list() async throws -> WebsitesResponse { throw WebsitesWriteQueueExecutorStubError.unused }
    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func save(url: String) async throws -> WebsiteSaveJobResponse {
        _ = url
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func jobStatus(id: String) async throws -> WebsiteJobStatusResponse {
        _ = id
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func cancel(jobId: String) async throws {
        _ = jobId
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
        throw WebsitesWriteQueueExecutorStubError.unused
    }
    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        throw WebsitesWriteQueueExecutorStubError.unused
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        let operationId = payload.operations.first?.operationId ?? "op"
        return WebsiteSyncResponse(
            applied: [operationId],
            websites: [
                makeItem(id: "website-1"),
                makeItem(id: "website-2")
            ],
            conflicts: [],
            updates: WebsiteSyncUpdates(items: [makeItem(id: "website-3")]),
            serverUpdatedSince: nil
        )
    }

    private func makeItem(id: String) -> WebsiteItem {
        WebsiteItem(
            id: id,
            title: id,
            url: "https://example.com/\(id)",
            domain: "example.com",
            savedAt: "2026-04-12T10:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-04-12T10:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
    }
}

private enum WebsitesWriteQueueExecutorStubError: Error {
    case unused
}
