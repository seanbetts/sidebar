import Foundation
@testable import sideBar

final class TestCacheClient: CacheClient {
    private struct Entry {
        let expiresAt: Date
        let data: Data
    }

    private var storage: [String: Entry] = [:]
    private let lock = NSLock()

    func get<T: Codable>(key: String) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[key] else {
            return nil
        }
        if Date() > entry.expiresAt {
            storage.removeValue(forKey: key)
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(T.self, from: entry.data)
    }

    func set<T: Codable>(key: String, value: T, ttlSeconds: TimeInterval) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else {
            return
        }
        lock.lock()
        storage[key] = Entry(expiresAt: Date().addingTimeInterval(ttlSeconds), data: data)
        lock.unlock()
    }

    func remove(key: String) {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}
