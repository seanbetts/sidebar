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
        let started = expectation(description: "background refresh started")
        let finished = expectation(description: "background refresh finished")
        store.onBackgroundRefreshStart = {
            started.fulfill()
        }
        store.onBackgroundRefresh = {
            finished.fulfill()
        }
        store.makeBackgroundRefreshWait()

        try await store.loadWithCache()
        await fulfillment(of: [started], timeout: 1.0)
        try await store.loadWithCache()

        XCTAssertEqual(store.backgroundRefreshCallCount, 1)
        await store.releaseBackgroundRefreshWait()
        await fulfillment(of: [finished], timeout: 1.0)
    }

    func testLoadWithCacheBacksOffAfterRepeatedFailures() async throws {
        let cache = TestCacheClient()
        cache.set(key: "store-key", value: "cached", ttlSeconds: 60)
        var now = Date(timeIntervalSince1970: 1_000)
        let store = MockCachedStore(cache: cache, fetchResult: "fresh", now: { now })
        store.backgroundRefreshOutcomes = [.failure, .failure, .success]

        let firstRefresh = expectation(description: "first background refresh finished")
        store.onBackgroundRefresh = {
            firstRefresh.fulfill()
        }
        try await store.loadWithCache()
        await fulfillment(of: [firstRefresh], timeout: 1.0)
        let secondRefresh = expectation(description: "second background refresh finished")
        store.onBackgroundRefresh = {
            secondRefresh.fulfill()
        }
        try await store.loadWithCache()
        await fulfillment(of: [secondRefresh], timeout: 1.0)
        XCTAssertEqual(store.backgroundRefreshCallCount, 2)

        try await store.loadWithCache()
        XCTAssertEqual(store.backgroundRefreshCallCount, 2)

        now = now.addingTimeInterval(5)
        let thirdRefresh = expectation(description: "third background refresh finished")
        store.onBackgroundRefresh = {
            thirdRefresh.fulfill()
        }
        try await store.loadWithCache()
        await fulfillment(of: [thirdRefresh], timeout: 1.0)
        XCTAssertEqual(store.backgroundRefreshCallCount, 3)
    }

    func testResetBackgroundRefreshBackoffAllowsImmediateRetry() async throws {
        let cache = TestCacheClient()
        cache.set(key: "store-key", value: "cached", ttlSeconds: 60)
        let store = MockCachedStore(cache: cache, fetchResult: "fresh")
        store.backgroundRefreshOutcomes = [.failure, .failure, .success]

        let firstRefresh = expectation(description: "first background refresh finished")
        store.onBackgroundRefresh = {
            firstRefresh.fulfill()
        }
        try await store.loadWithCache()
        await fulfillment(of: [firstRefresh], timeout: 1.0)
        let secondRefresh = expectation(description: "second background refresh finished")
        store.onBackgroundRefresh = {
            secondRefresh.fulfill()
        }
        try await store.loadWithCache()
        await fulfillment(of: [secondRefresh], timeout: 1.0)
        XCTAssertEqual(store.backgroundRefreshCallCount, 2)

        try await store.loadWithCache()
        XCTAssertEqual(store.backgroundRefreshCallCount, 2)

        store.resetBackgroundRefreshBackoff()
        let thirdRefresh = expectation(description: "third background refresh finished")
        store.onBackgroundRefresh = {
            thirdRefresh.fulfill()
        }
        try await store.loadWithCache()
        await fulfillment(of: [thirdRefresh], timeout: 1.0)
        XCTAssertEqual(store.backgroundRefreshCallCount, 3)
    }

    func testRepeatedConcurrentCacheLoadsDoNotTriggerDuplicateBackgroundRefreshes() async throws {
        let cache = TestCacheClient()
        cache.set(key: "store-key", value: "cached", ttlSeconds: 60)
        let store = MockCachedStore(cache: cache, fetchResult: "fresh")
        let iterations = 6

        for iteration in 0..<iterations {
            let started = expectation(description: "background refresh started \(iteration)")
            let finished = expectation(description: "background refresh finished \(iteration)")
            store.onBackgroundRefreshStart = {
                started.fulfill()
            }
            store.onBackgroundRefresh = {
                finished.fulfill()
            }
            store.makeBackgroundRefreshWait()
            async let firstLoad: Void = store.loadWithCache()
            async let secondLoad: Void = store.loadWithCache()
            _ = try await (firstLoad, secondLoad)

            await fulfillment(of: [started], timeout: 1.0)
            XCTAssertEqual(
                store.backgroundRefreshCallCount,
                iteration + 1,
                "Iteration \(iteration) should only schedule one background refresh"
            )
            await store.releaseBackgroundRefreshWait()
            await fulfillment(of: [finished], timeout: 1.0)
        }
    }

    func testCoreDataCacheClientSetIsVisibleImmediatelyAfterCallReturns() async {
        let persistence = PersistenceController(inMemory: true)
        let cache = CoreDataCacheClient(container: persistence.container)

        cache.set(key: "greeting", value: "hello", ttlSeconds: 60)

        let value: String? = cache.get(key: "greeting")
        XCTAssertEqual(value, "hello")
    }

    func testInMemoryCacheClientDeallocatesCleanlyAfterUse() {
        weak var weakCache: InMemoryCacheClient?

        autoreleasepool {
            var cache: InMemoryCacheClient? = InMemoryCacheClient()
            cache?.set(key: "greeting", value: "hello", ttlSeconds: 60)

            let value: String? = cache?.get(key: "greeting")
            XCTAssertEqual(value, "hello")

            weakCache = cache
            cache = nil
        }

        XCTAssertNil(weakCache)
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
    var onBackgroundRefreshStart: (() -> Void)?
    var backgroundRefreshOutcomes: [BackgroundRefreshOutcome] = [.success]
    private(set) var backgroundRefreshCallCount = 0
    private var backgroundRefreshWait: BackgroundRefreshWait?

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
        onBackgroundRefreshStart?()
        if let backgroundRefreshWait {
            await backgroundRefreshWait.wait()
            self.backgroundRefreshWait = nil
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

    func makeBackgroundRefreshWait() {
        backgroundRefreshWait = BackgroundRefreshWait()
    }

    func releaseBackgroundRefreshWait() async {
        await backgroundRefreshWait?.release()
    }
}

private actor BackgroundRefreshWait {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
