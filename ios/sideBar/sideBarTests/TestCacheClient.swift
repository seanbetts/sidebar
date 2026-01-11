import Foundation
@testable import sideBar

final class TestCacheClient: CacheClient {
    private struct Entry {
        let expiresAt: Date
        let data: Data
    }

    private var storage: [String: Entry] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func get<T: Codable>(key: String) -> T? {
        guard let entry = storage[key] else {
            return nil
        }
        if Date() > entry.expiresAt {
            storage.removeValue(forKey: key)
            return nil
        }
        return try? decoder.decode(T.self, from: entry.data)
    }

    func set<T: Codable>(key: String, value: T, ttlSeconds: TimeInterval) {
        guard let data = try? encoder.encode(value) else {
            return
        }
        storage[key] = Entry(expiresAt: Date().addingTimeInterval(ttlSeconds), data: data)
    }

    func remove(key: String) {
        storage.removeValue(forKey: key)
    }

    func clear() {
        storage.removeAll()
    }
}
