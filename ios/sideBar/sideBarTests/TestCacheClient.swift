import Foundation
import sideBarShared
import os
@testable import sideBar

/// Test cache client using OSAllocatedUnfairLock for Swift 6 safe synchronization.
final class TestCacheClient: CacheClient, @unchecked Sendable {
    private struct Entry: Sendable {
        let expiresAt: Date
        let data: Data
    }

    private let storage = OSAllocatedUnfairLock(initialState: [String: Entry]())

    func get<T: Codable>(key: String) -> T? {
        storage.withLock { store in
            guard let entry = store[key] else {
                return nil
            }
            if Date() > entry.expiresAt {
                store.removeValue(forKey: key)
                return nil
            }
            let decoder = JSONDecoder()
            return try? decoder.decode(T.self, from: entry.data)
        }
    }

    func set<T: Codable>(key: String, value: T, ttlSeconds: TimeInterval) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else {
            return
        }
        storage.withLock { store in
            store[key] = Entry(expiresAt: Date().addingTimeInterval(ttlSeconds), data: data)
        }
    }

    func remove(key: String) {
        storage.withLock { store in
            store.removeValue(forKey: key)
        }
    }

    func clear() {
        storage.withLock { store in
            store.removeAll()
        }
    }
}
