import Darwin
import Foundation

public final class WidgetPendingOperationStore {
    private static let processLock = NSRecursiveLock()
    private let userDefaultsProvider: () -> UserDefaults?
    private let lockFileURLProvider: () -> URL?

    public init(
        userDefaultsProvider: @escaping () -> UserDefaults?,
        lockFileURLProvider: @escaping () -> URL? = { nil }
    ) {
        self.userDefaultsProvider = userDefaultsProvider
        self.lockFileURLProvider = lockFileURLProvider
    }

    public convenience init(
        userDefaultsProvider: @escaping () -> UserDefaults?,
        appGroupResolutionProvider: @escaping () -> WidgetBridgeAppGroupResolution
    ) {
        self.init(
            userDefaultsProvider: userDefaultsProvider,
            lockFileURLProvider: {
                Self.appGroupLockFileURL(for: appGroupResolutionProvider())
            }
        )
    }

    public func load<A: Codable & Equatable>(
        key: String,
        actionType: A.Type
    ) -> [WidgetPendingOperation<A>] {
        withLock {
            guard let defaults = userDefaultsProvider() else { return [] }
            defaults.synchronize()
            return loadUnlocked(defaults: defaults, key: key)
        }
    }

    public func record<A: Codable & Equatable>(
        _ operation: WidgetPendingOperation<A>,
        key: String
    ) -> Int? {
        withLock {
            guard let defaults = userDefaultsProvider() else { return nil }
            defaults.synchronize()
            var pending: [WidgetPendingOperation<A>] = loadUnlocked(defaults: defaults, key: key)
            guard !pending.contains(where: { $0.itemId == operation.itemId && $0.action == operation.action }) else {
                return nil
            }

            pending.append(operation)
            guard let encoded = try? Self.makeEncoder().encode(pending) else { return nil }
            defaults.set(encoded, forKey: key)
            defaults.synchronize()
            return pending.count
        }
    }

    public func consume<A: Codable & Equatable>(
        key: String,
        actionType: A.Type
    ) -> [WidgetPendingOperation<A>]? {
        withLock {
            guard let defaults = userDefaultsProvider() else { return nil }
            defaults.synchronize()
            let pending: [WidgetPendingOperation<A>] = loadUnlocked(defaults: defaults, key: key)
            defaults.removeObject(forKey: key)
            defaults.synchronize()
            return pending
        }
    }

    public func consume<A: Codable & Equatable>(
        key: String,
        actionType: A.Type,
        matching: (A) -> Bool
    ) -> (matched: [WidgetPendingOperation<A>], remainingCount: Int)? {
        withLock {
            guard let defaults = userDefaultsProvider() else { return nil }
            defaults.synchronize()
            let pending: [WidgetPendingOperation<A>] = loadUnlocked(defaults: defaults, key: key)
            guard !pending.isEmpty else { return nil }

            let matched = pending.filter { matching($0.action) }
            let remaining = pending.filter { !matching($0.action) }
            saveUnlocked(remaining, defaults: defaults, key: key)
            return (matched, remaining.count)
        }
    }

    public func remove<A: Codable & Equatable>(
        id operationId: String,
        key: String,
        actionType: A.Type
    ) -> Int? {
        withLock {
            guard let defaults = userDefaultsProvider() else { return nil }
            defaults.synchronize()
            let pending: [WidgetPendingOperation<A>] = loadUnlocked(defaults: defaults, key: key)
            guard !pending.isEmpty else { return nil }

            let filtered = pending.filter { $0.id != operationId }
            guard filtered.count != pending.count else { return nil }

            saveUnlocked(filtered, defaults: defaults, key: key)
            return filtered.count
        }
    }

    private func loadUnlocked<A: Codable & Equatable>(
        defaults: UserDefaults,
        key: String
    ) -> [WidgetPendingOperation<A>] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? Self.makeDecoder().decode([WidgetPendingOperation<A>].self, from: data)) ?? []
    }

    private func saveUnlocked<A: Codable & Equatable>(
        _ pending: [WidgetPendingOperation<A>],
        defaults: UserDefaults,
        key: String
    ) {
        if pending.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let encoded = try? Self.makeEncoder().encode(pending) {
            defaults.set(encoded, forKey: key)
        }
        defaults.synchronize()
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }

        guard let lockFileURL = lockFileURLProvider() else {
            return operation()
        }

        return withFileLock(at: lockFileURL, operation)
    }

    private func withFileLock<T>(at lockFileURL: URL, _ operation: () -> T) -> T {
        let directoryURL = lockFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            return operation()
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            return operation()
        }
        defer { flock(descriptor, LOCK_UN) }

        return operation()
    }

    private static func appGroupLockFileURL(for resolution: WidgetBridgeAppGroupResolution) -> URL? {
        guard let appGroupId = resolution.id,
              let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupId
              ) else {
            return nil
        }

        return containerURL
            .appendingPathComponent("WidgetPendingOperationStore", isDirectory: true)
            .appendingPathComponent("pending-operations.lock", isDirectory: false)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
