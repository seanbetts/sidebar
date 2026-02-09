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

    func testLoadWithCacheCoalescesBackgroundRefreshWhenAlreadyRunning() async throws {
        let cache = TestCacheClient()
        cache.set(key: "store-key", value: "cached", ttlSeconds: 60)
        let store = MockCachedStore(cache: cache, fetchResult: "fresh")
        store.backgroundRefreshDelay = 300_000_000

        try await store.loadWithCache()
        try await store.loadWithCache()
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(store.backgroundRefreshCallCount, 1)
    }

    func testLoadWithCacheBacksOffAfterRepeatedFailures() async throws {
        let cache = TestCacheClient()
        cache.set(key: "store-key", value: "cached", ttlSeconds: 60)
        var now = Date(timeIntervalSince1970: 1_000)
        let store = MockCachedStore(cache: cache, fetchResult: "fresh", now: { now })
        store.backgroundRefreshOutcomes = [.failure, .failure, .success]

        try await store.loadWithCache()
        await waitForBackgroundTask()
        try await store.loadWithCache()
        await waitForBackgroundTask()
        XCTAssertEqual(store.backgroundRefreshCallCount, 2)

        try await store.loadWithCache()
        await waitForBackgroundTask()
        XCTAssertEqual(store.backgroundRefreshCallCount, 2)

        now = now.addingTimeInterval(5)
        try await store.loadWithCache()
        await waitForBackgroundTask()
        XCTAssertEqual(store.backgroundRefreshCallCount, 3)
    }

    func testResetBackgroundRefreshBackoffAllowsImmediateRetry() async throws {
        let cache = TestCacheClient()
        cache.set(key: "store-key", value: "cached", ttlSeconds: 60)
        let store = MockCachedStore(cache: cache, fetchResult: "fresh")
        store.backgroundRefreshOutcomes = [.failure, .failure, .success]

        try await store.loadWithCache()
        await waitForBackgroundTask()
        try await store.loadWithCache()
        await waitForBackgroundTask()
        XCTAssertEqual(store.backgroundRefreshCallCount, 2)

        try await store.loadWithCache()
        await waitForBackgroundTask()
        XCTAssertEqual(store.backgroundRefreshCallCount, 2)

        store.resetBackgroundRefreshBackoff()
        try await store.loadWithCache()
        await waitForBackgroundTask()
        XCTAssertEqual(store.backgroundRefreshCallCount, 3)
    }

    func testRepeatedConcurrentCacheLoadsDoNotTriggerDuplicateBackgroundRefreshes() async throws {
        let cache = TestCacheClient()
        cache.set(key: "store-key", value: "cached", ttlSeconds: 60)
        let store = MockCachedStore(cache: cache, fetchResult: "fresh")
        store.backgroundRefreshDelay = 200_000_000
        let iterations = 6

        for iteration in 0..<iterations {
            async let firstLoad: Void = store.loadWithCache()
            async let secondLoad: Void = store.loadWithCache()
            _ = try await (firstLoad, secondLoad)

            try? await Task.sleep(nanoseconds: 325_000_000)
            XCTAssertEqual(
                store.backgroundRefreshCallCount,
                iteration + 1,
                "Iteration \(iteration) should only schedule one background refresh"
            )
        }
    }

    private func waitForBackgroundTask() async {
        try? await Task.sleep(nanoseconds: 75_000_000)
    }
}

@MainActor
private final class MockCachedStore: CachedStoreBase<String> {
    enum BackgroundRefreshOutcome {
        case success
        case failure
    }

    struct Applied {
        let value: String
        let persist: Bool
    }

    override var cacheKey: String { "store-key" }
    override var cacheTTL: TimeInterval { 60 }
    let fetchResult: String
    var appliedData: [Applied] = []
    var onBackgroundRefresh: (() -> Void)?
    var backgroundRefreshDelay: UInt64 = 0
    var backgroundRefreshOutcomes: [BackgroundRefreshOutcome] = [.success]
    private(set) var backgroundRefreshCallCount = 0

    init(
        cache: CacheClient,
        fetchResult: String,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetchResult = fetchResult
        super.init(cache: cache, now: now)
    }

    override func fetchFromAPI() async throws -> String {
        fetchResult
    }

    override func applyData(_ data: String, persist: Bool) {
        appliedData.append(Applied(value: data, persist: persist))
    }

    override func backgroundRefresh() async {
        backgroundRefreshCallCount += 1
        if backgroundRefreshDelay > 0 {
            try? await Task.sleep(nanoseconds: backgroundRefreshDelay)
        }
        let outcome = backgroundRefreshOutcomes.isEmpty ? .success : backgroundRefreshOutcomes.removeFirst()
        switch outcome {
        case .success:
            markBackgroundRefreshSuccess()
        case .failure:
            markBackgroundRefreshFailure()
        }
        onBackgroundRefresh?()
    }
}
