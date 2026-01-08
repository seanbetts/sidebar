import Foundation

public protocol CacheClient {
    func get<T: Codable>(key: String) -> T?
    func set<T: Codable>(key: String, value: T, ttlSeconds: TimeInterval)
    func remove(key: String)
}

public final class InMemoryCacheClient: CacheClient {
    private struct Entry {
        let expiresAt: Date
        let data: Data
    }

    private var storage: [String: Entry] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
    }

    public func get<T: Codable>(key: String) -> T? {
        guard let entry = storage[key] else {
            return nil
        }
        if Date() > entry.expiresAt {
            storage.removeValue(forKey: key)
            return nil
        }
        return try? decoder.decode(T.self, from: entry.data)
    }

    public func set<T: Codable>(key: String, value: T, ttlSeconds: TimeInterval) {
        guard let data = try? encoder.encode(value) else {
            return
        }
        let entry = Entry(expiresAt: Date().addingTimeInterval(ttlSeconds), data: data)
        storage[key] = entry
    }

    public func remove(key: String) {
        storage.removeValue(forKey: key)
    }
}
