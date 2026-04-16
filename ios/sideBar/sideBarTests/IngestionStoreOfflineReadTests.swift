import Foundation
import XCTest
@testable import sideBar

@MainActor
final class IngestionStoreOfflineReadTests: XCTestCase {
    func testLoadListUsesOfflineCacheWhenServerUnreachable() async throws {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        let expected = IngestionListResponse(
            items: [IngestionStoreTestsSupport.makeItem(id: "cached-file", status: "ready", stage: "ready")]
        )
        offlineStore.set(
            key: CacheKeys.ingestionList,
            entityType: "ingestionList",
            value: expected,
            lastSyncAt: nil
        )
        let api = OfflineAwareIngestionListAPI()
        let store = IngestionStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: OfflineAwareNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            ),
            userDefaults: defaults
        )

        try await store.loadList()

        XCTAssertEqual(store.items.map(\.file.id), ["cached-file"])
        XCTAssertEqual(api.listCallCount, 0)
    }
}

private struct OfflineAwareNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool
    let isServerReachable: Bool
}

private final class OfflineAwareIngestionListAPI: IngestionProviding {
    private(set) var listCallCount = 0

    func list() async throws -> IngestionListResponse {
        listCallCount += 1
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        _ = fileId
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = fileId
        _ = kind
        _ = range
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func upload(fileURL: URL, filename: String, mimeType: String, folder: String) async throws -> String {
        _ = fileURL
        _ = filename
        _ = mimeType
        _ = folder
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func cancel(fileId: String) async throws {
        _ = fileId
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func delete(fileId: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = clientUpdatedAt
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = filename
        _ = clientUpdatedAt
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        throw IngestionStoreTestsSupport.MockError.forced
    }
}
