import Combine
import Foundation
import OSLog

public protocol CacheClient {
    func get<T: Codable>(key: String) -> T?
    func set<T: Codable>(key: String, value: T, ttlSeconds: TimeInterval)
    func remove(key: String)
    func clear()
}

public extension CacheClient {
    /// Invalidate a list cache and optionally a related detail cache.
    func invalidateList(
        listKey: String,
        detailKey: ((String) -> String)? = nil,
        id: String? = nil
    ) {
        remove(key: listKey)
        if let detailKey, let id {
            remove(key: detailKey(id))
        }
    }
}

/// In-memory cache implementation for ephemeral data.
public final class InMemoryCacheClient: CacheClient {
    private struct Entry {
        let expiresAt: Date
        let data: Data
    }

    private var storage: [String: Entry] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "sideBar", category: "Cache")

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
        do {
            return try decoder.decode(T.self, from: entry.data)
        } catch {
            logger.error("Cache decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func set<T: Codable>(key: String, value: T, ttlSeconds: TimeInterval) {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            logger.error("Cache encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let entry = Entry(expiresAt: Date().addingTimeInterval(ttlSeconds), data: data)
        storage[key] = entry
    }

    public func remove(key: String) {
        storage.removeValue(forKey: key)
    }

    public func clear() {
        storage.removeAll()
    }
}
