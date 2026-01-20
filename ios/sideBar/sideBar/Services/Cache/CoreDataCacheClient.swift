import CoreData
import Foundation
import OSLog

/// Core Data-backed cache implementation.
public final class CoreDataCacheClient: CacheClient {
    private let container: NSPersistentContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "sideBar", category: "Cache")

    public init(container: NSPersistentContainer) {
        self.container = container
    }

    public func get<T: Codable>(key: String) -> T? {
        var decoded: T?
        let context = container.viewContext
        context.performAndWait {
            let request = CacheEntry.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)

            do {
                guard let entry = try context.fetch(request).first else {
                    return
                }

                if Date() > entry.expiresAt {
                    context.delete(entry)
                    do {
                        try context.save()
                    } catch {
                        logger.error("Cache entry cleanup failed: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }

                do {
                    decoded = try decoder.decode(T.self, from: entry.payload)
                } catch {
                    logger.error("Cache decode failed: \(error.localizedDescription, privacy: .public)")
                }
            } catch {
                logger.error("Cache fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return decoded
    }

    public func set<T: Codable>(key: String, value: T, ttlSeconds: TimeInterval) {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            logger.error("Cache encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let now = Date()
        let expiresAt = now.addingTimeInterval(ttlSeconds)
        let typeName = String(reflecting: T.self)

        container.performBackgroundTask { context in
            let request = CacheEntry.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)

            let entry: CacheEntry
            do {
                entry = try context.fetch(request).first ?? CacheEntry(context: context)
            } catch {
                logger.error("Cache fetch failed: \(error.localizedDescription, privacy: .public)")
                entry = CacheEntry(context: context)
            }
            entry.key = key
            entry.payload = data
            entry.expiresAt = expiresAt
            entry.updatedAt = now
            entry.typeName = typeName
            if entry.createdAt == nil {
                entry.createdAt = now
            }

            do {
                try context.save()
            } catch {
                logger.error("Cache save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func remove(key: String) {
        let context = container.viewContext
        context.performAndWait {
            let request = CacheEntry.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", key)
            do {
                let items = try context.fetch(request)
                for item in items {
                    context.delete(item)
                }
                try context.save()
            } catch {
                logger.error("Cache remove failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func clear() {
        let context = container.viewContext
        context.performAndWait {
            let request = CacheEntry.fetchRequest()
            do {
                let items = try context.fetch(request)
                for item in items {
                    context.delete(item)
                }
                try context.save()
            } catch {
                logger.error("Cache clear failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
