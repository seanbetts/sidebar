import CoreData
import Foundation

public final class CoreDataCacheClient: CacheClient {
    private let container: NSPersistentContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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

            guard let entry = try? context.fetch(request).first else {
                return
            }

            if Date() > entry.expiresAt {
                context.delete(entry)
                try? context.save()
                return
            }

            decoded = try? decoder.decode(T.self, from: entry.payload)
        }
        return decoded
    }

    public func set<T: Codable>(key: String, value: T, ttlSeconds: TimeInterval) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        let now = Date()
        let expiresAt = now.addingTimeInterval(ttlSeconds)
        let typeName = String(reflecting: T.self)

        container.performBackgroundTask { context in
            let request = CacheEntry.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)

            let entry = (try? context.fetch(request).first) ?? CacheEntry(context: context)
            entry.key = key
            entry.payload = data
            entry.expiresAt = expiresAt
            entry.updatedAt = now
            entry.typeName = typeName
            if entry.createdAt == nil {
                entry.createdAt = now
            }

            try? context.save()
        }
    }

    public func remove(key: String) {
        let context = container.viewContext
        context.performAndWait {
            let request = CacheEntry.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", key)
            let items = (try? context.fetch(request)) ?? []
            for item in items {
                context.delete(item)
            }
            try? context.save()
        }
    }
}
