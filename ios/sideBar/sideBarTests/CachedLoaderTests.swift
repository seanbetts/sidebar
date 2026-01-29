import XCTest
import sideBarShared
@testable import sideBar

final class CachedLoaderTests: XCTestCase {
    func testLoadReturnsCachedDataAndRefreshes() async throws {
        let cache = TestCacheClient()
        cache.set(key: "cached-key", value: "cached", ttlSeconds: 60)
        let refreshExpectation = expectation(description: "refresh")

        let loader = CachedLoader<String>(
            cache: cache,
            key: "cached-key",
            ttl: 60
        ) {
            "fresh"
        }

        let (value, fromCache) = try await loader.load(onRefresh: { fresh in
            XCTAssertEqual(fresh, "fresh")
            refreshExpectation.fulfill()
        })

        XCTAssertEqual(value, "cached")
        XCTAssertTrue(fromCache)

        await fulfillment(of: [refreshExpectation], timeout: 1.0)
        let refreshed: String? = cache.get(key: "cached-key")
        XCTAssertEqual(refreshed, "fresh")
    }

    func testLoadFetchesRemoteWhenCacheMissing() async throws {
        let cache = TestCacheClient()
        let loader = CachedLoader<String>(
            cache: cache,
            key: "missing-key",
            ttl: 60
        ) {
            "remote"
        }

        let (value, fromCache) = try await loader.load()

        XCTAssertEqual(value, "remote")
        XCTAssertFalse(fromCache)
        let cached: String? = cache.get(key: "missing-key")
        XCTAssertEqual(cached, "remote")
    }

    func testLoadForceBypassesCache() async throws {
        let cache = TestCacheClient()
        cache.set(key: "force-key", value: "cached", ttlSeconds: 60)
        let loader = CachedLoader<String>(
            cache: cache,
            key: "force-key",
            ttl: 60
        ) {
            "remote"
        }

        let (value, fromCache) = try await loader.load(force: true)

        XCTAssertEqual(value, "remote")
        XCTAssertFalse(fromCache)
        let cached: String? = cache.get(key: "force-key")
        XCTAssertEqual(cached, "remote")
    }
}
