import Foundation
import Combine

/// Base class for stores with cache-first loading.
/// Subclasses must override `cacheKey`, `cacheTTL`, `fetchFromAPI()`, `applyData()`, and `backgroundRefresh()`.
@MainActor
open class CachedStoreBase<CachedData: Codable>: ObservableObject {
    /// Indicates where data was resolved during a cache-first load.
    public enum CacheLoadSource {
        case cache
        case offline
        case remote
    }

    public let objectWillChange = ObservableObjectPublisher()
    public let cache: CacheClient
    private var backgroundRefreshTask: Task<Void, Never>?
    private let backgroundRefreshFailuresBeforeBackoff: Int
    private let backgroundRefreshBaseDelay: TimeInterval
    private let backgroundRefreshMaxDelay: TimeInterval
    private let now: () -> Date
    private(set) var consecutiveBackgroundRefreshFailures = 0
    private(set) var nextBackgroundRefreshAllowedAt: Date?

    open var cacheKey: String {
        fatalError("Subclass must override cacheKey")
    }

    open var cacheTTL: TimeInterval {
        fatalError("Subclass must override cacheTTL")
    }

    public init(
        cache: CacheClient,
        backgroundRefreshFailuresBeforeBackoff: Int = 2,
        backgroundRefreshBaseDelay: TimeInterval = 5,
        backgroundRefreshMaxDelay: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) {
        self.cache = cache
        self.backgroundRefreshFailuresBeforeBackoff = max(1, backgroundRefreshFailuresBeforeBackoff)
        self.backgroundRefreshBaseDelay = max(1, backgroundRefreshBaseDelay)
        self.backgroundRefreshMaxDelay = max(backgroundRefreshBaseDelay, backgroundRefreshMaxDelay)
        self.now = now
    }

    open func fetchFromAPI() async throws -> CachedData {
        fatalError("Subclass must override fetchFromAPI()")
    }

    open func applyData(_ data: CachedData, persist: Bool) {
        fatalError("Subclass must override applyData(_:persist:)")
    }

    open func backgroundRefresh() async {
        fatalError("Subclass must override backgroundRefresh()")
    }

    public func loadWithCache(force: Bool = false) async throws {
        _ = try await loadWithCacheAndOffline(force: force)
    }

    @discardableResult
    public func loadWithCacheAndOffline(
        force: Bool = false,
        offline: (() -> CachedData?)? = nil,
        isNetworkAvailable: Bool = true,
        remoteUnavailableError: (() -> Error)? = nil
    ) async throws -> CacheLoadSource {
        let cached: CachedData? = force ? nil : cache.get(key: cacheKey)

        if let cached {
            applyData(cached, persist: false)
            triggerBackgroundRefresh()
            return .cache
        }

        if !force, let offlineData = offline?() {
            applyData(offlineData, persist: false)
            if isNetworkAvailable {
                triggerBackgroundRefresh()
            }
            return .offline
        }

        if !isNetworkAvailable, let remoteUnavailableError {
            throw remoteUnavailableError()
        }

        let remote = try await fetchFromAPI()
        applyData(remote, persist: true)
        cache.set(key: cacheKey, value: remote, ttlSeconds: cacheTTL)
        return .remote
    }

    public func markBackgroundRefreshSuccess() {
        consecutiveBackgroundRefreshFailures = 0
        nextBackgroundRefreshAllowedAt = nil
    }

    @discardableResult
    public func applyDataIfChanged(
        _ data: CachedData,
        currentData: CachedData?,
        persist: Bool,
        isEqual: (CachedData, CachedData) -> Bool
    ) -> Bool {
        if let currentData, isEqual(currentData, data) {
            if persist {
                cache.set(key: cacheKey, value: data, ttlSeconds: cacheTTL)
            }
            return false
        }

        applyData(data, persist: persist)
        if persist {
            cache.set(key: cacheKey, value: data, ttlSeconds: cacheTTL)
        }
        return true
    }

    func enqueueOfflineOperation<Payload: Encodable>(
        writeQueue: WriteQueue?,
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String?,
        payload: Payload,
        serverSnapshot: ServerSnapshot? = nil
    ) async throws {
        guard let writeQueue else {
            throw WriteQueueError.missingQueue
        }
        try await writeQueue.enqueue(
            operation: operation,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            serverSnapshot: serverSnapshot
        )
    }

    public func markBackgroundRefreshFailure() {
        consecutiveBackgroundRefreshFailures += 1
        guard consecutiveBackgroundRefreshFailures >= backgroundRefreshFailuresBeforeBackoff else {
            return
        }

        let exponent = Double(consecutiveBackgroundRefreshFailures - backgroundRefreshFailuresBeforeBackoff)
        let multiplier = pow(2.0, exponent)
        let delay = min(backgroundRefreshMaxDelay, backgroundRefreshBaseDelay * multiplier)
        nextBackgroundRefreshAllowedAt = now().addingTimeInterval(delay)
    }

    public func resetBackgroundRefreshBackoff() {
        consecutiveBackgroundRefreshFailures = 0
        nextBackgroundRefreshAllowedAt = nil
    }

    func canAttemptBackgroundRefresh() -> Bool {
        guard let nextBackgroundRefreshAllowedAt else {
            return true
        }
        return now() >= nextBackgroundRefreshAllowedAt
    }

    private func triggerBackgroundRefresh() {
        guard canAttemptBackgroundRefresh() else { return }
        guard backgroundRefreshTask == nil else { return }
        backgroundRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.backgroundRefreshTask = nil }
            await self.backgroundRefresh()
        }
    }
}
