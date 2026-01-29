import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class CachedStoreTests: XCTestCase {
    func testLoadWithCacheUsesCachedAndRefreshes() async throws {
        let cache = TestCacheClient()
        cache.set(key: "store-key", value: "cached", ttlSeconds: 60)
        let store = MockCachedStore(cache: cache, fetchResult: "fresh")
        let refreshExpectation = expectation(description: "refresh")
        store.onBackgroundRefresh = {
            refreshExpectation.fulfill()
        }

        try await store.loadWithCache()

        XCTAssertEqual(store.appliedData.first?.value, "cached")
        XCTAssertEqual(store.appliedData.first?.persist, false)
        await fulfillment(of: [refreshExpectation], timeout: 1.0)
    }

    func testLoadWithCacheFetchesWhenMissing() async throws {
        let cache = TestCacheClient()
        let store = MockCachedStore(cache: cache, fetchResult: "fresh")

        try await store.loadWithCache()

        XCTAssertEqual(store.appliedData.first?.value, "fresh")
        XCTAssertEqual(store.appliedData.first?.persist, true)
        let cached: String? = cache.get(key: "store-key")
        XCTAssertEqual(cached, "fresh")
    }
}

@MainActor
private final class MockCachedStore: CachedStoreBase<String> {
    struct Applied {
        let value: String
        let persist: Bool
    }

    override var cacheKey: String { "store-key" }
    override var cacheTTL: TimeInterval { 60 }
    let fetchResult: String
    var appliedData: [Applied] = []
    var onBackgroundRefresh: (() -> Void)?

    init(cache: CacheClient, fetchResult: String) {
        self.fetchResult = fetchResult
        super.init(cache: cache)
    }

    override func fetchFromAPI() async throws -> String {
        fetchResult
    }

    override func applyData(_ data: String, persist: Bool) {
        appliedData.append(Applied(value: data, persist: persist))
    }

    override func backgroundRefresh() async {
        onBackgroundRefresh?()
    }
}
