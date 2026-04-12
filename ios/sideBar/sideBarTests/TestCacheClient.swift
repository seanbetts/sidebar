import Foundation
import sideBarShared
@testable import sideBar

/// Thread-safe test cache client.
final class TestCacheClient: CacheClient, @unchecked Sendable {
    private struct Entry: Sendable {
        let expiresAt: Date
        let data: Data
    }

    private var storage: [String: Entry] = [:]
    private var removedKeys: [String] = []
    private let lock = NSLock()

    func get<T: Codable>(key: String) -> T? {
        lock.lock()
        guard let entry = storage[key] else {
            lock.unlock()
            return nil
        }
        if Date() > entry.expiresAt {
            storage.removeValue(forKey: key)
            lock.unlock()
            return nil
        }
        lock.unlock()
        let decoder = JSONDecoder()
        return try? decoder.decode(T.self, from: entry.data)
    }

    func setEncoded(key: String, payload data: Data, typeName _: String, ttlSeconds: TimeInterval) {
        lock.lock()
        storage[key] = Entry(expiresAt: Date().addingTimeInterval(ttlSeconds), data: data)
        lock.unlock()
    }

    func remove(key: String) {
        lock.lock()
        _ = storage.removeValue(forKey: key)
        removedKeys.append(key)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }

    func removedKeysSnapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return removedKeys
    }
}
