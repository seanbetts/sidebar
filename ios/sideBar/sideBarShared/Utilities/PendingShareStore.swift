import Foundation
import os.log

/// Represents a queued share payload category persisted between extension and app.
public enum PendingShareKind: String, Codable {
    case website
    case file
    case image
    case youtube
}

/// Represents a single queued share payload persisted for deferred processing.
public struct PendingShareItem: Codable, Equatable, Identifiable {
    /// Unique identifier for the queued share item.
    public let id: UUID
    /// Share payload category for downstream routing.
    public let kind: PendingShareKind
    /// Timestamp when the item was queued.
    public let createdAt: Date
    /// Shared website URL when kind is `.website` or `.youtube`.
    public let url: String?
    /// Relative file path for copied binary payloads.
    public let filePath: String?
    /// Original filename supplied by the share source.
    public let filename: String?
    /// MIME type for binary payload processing.
    public let mimeType: String?
    /// Number of failed retry attempts made by the main app processor.
    public let retryCount: Int?
    /// Earliest timestamp when this item should be retried again.
    public let nextRetryAt: Date?
    /// Last failure message captured while processing this item.
    public let lastError: String?
    /// Backend website-save job identifier for accepted website shares awaiting completion.
    public let websiteJobId: String?

    /// Creates a queued share payload model.
    public init(
        id: UUID,
        kind: PendingShareKind,
        createdAt: Date,
        url: String? = nil,
        filePath: String? = nil,
        filename: String? = nil,
        mimeType: String? = nil,
        retryCount: Int? = nil,
        nextRetryAt: Date? = nil,
        lastError: String? = nil,
        websiteJobId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.url = url
        self.filePath = filePath
        self.filename = filename
        self.mimeType = mimeType
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
        self.websiteJobId = websiteJobId
    }
}

/// Stores pending share payloads in app-group storage for later app ingestion.
public final class PendingShareStore {
    /// Process-wide shared pending-share store instance.
    public static let shared = PendingShareStore()

    static let log = OSLog(subsystem: "ai.sidebar.sidebar", category: "PendingShareStore")

    private let itemsKey = "pendingShareItems"
    private let directoryName = "pending-shares"
    private let fileManager: FileManager
    private let baseDirectory: URL?
    private let userDefaults: UserDefaults?
    private let allowAppGroupFallback: Bool
    private let accessLock = NSRecursiveLock()

    /// Creates a pending-share store with injectable storage dependencies for tests.
    public init(
        baseDirectory: URL? = nil,
        userDefaults: UserDefaults? = nil,
        allowAppGroupFallback: Bool = true,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.userDefaults = userDefaults
        self.allowAppGroupFallback = allowAppGroupFallback
        self.fileManager = fileManager
    }

    /// Returns whether website/youtube queue metadata can be persisted.
    public func canQueueURLItems() -> Bool {
        withAccessLock {
            hasRequiredStorage(needsFileContainer: false, context: "canQueueURLItems")
        }
    }

    /// Returns whether file/image queue payloads can be persisted.
    public func canQueueFileItems() -> Bool {
        withAccessLock {
            hasRequiredStorage(needsFileContainer: true, context: "canQueueFileItems")
        }
    }

    @discardableResult
    /// Enqueues a website URL share if not already present.
    public func enqueueWebsite(url: String) -> PendingShareItem? {
        withAccessLock {
            let redactedURL = LogRedaction.redactedURLString(url)
            guard hasRequiredStorage(needsFileContainer: false, context: "enqueueWebsite") else {
                recordDiagnostics(
                    stage: "enqueue_website_missing_storage",
                    message: "Could not queue website because shared storage was unavailable.",
                    metadata: ["url": redactedURL]
                )
                return nil
            }
            let existingItems = loadAll()
            if let existing = existingItems.first(where: { $0.kind == .website && $0.url == url }) {
                os_log(.default, log: Self.log, "Website share already queued %{public}@", redactedURL)
                recordDiagnostics(
                    stage: "enqueue_website_duplicate",
                    message: "Website was already queued.",
                    metadata: [
                        "url": redactedURL,
                        "queue_item_id": existing.id.uuidString
                    ]
                )
                return existing
            }
            let item = PendingShareItem(
                id: UUID(),
                kind: .website,
                createdAt: Date(),
                url: url
            )
            var items = existingItems
            items.append(item)
            replaceAll(items)
            WebsiteSaveHandoffNotifier.post()
            os_log(.default, log: Self.log, "Queued website share %{public}@", redactedURL)
            recordDiagnostics(
                stage: "enqueue_website",
                message: "Queued website share.",
                metadata: [
                    "url": redactedURL,
                    "queue_item_id": item.id.uuidString,
                    "count": "\(items.count)"
                ]
            )
            return item
        }
    }

    @discardableResult
    /// Enqueues a YouTube URL share if not already present.
    public func enqueueYouTube(url: String) -> PendingShareItem? {
        withAccessLock {
            let redactedURL = LogRedaction.redactedURLString(url)
            guard hasRequiredStorage(needsFileContainer: false, context: "enqueueYouTube") else {
                return nil
            }
            let existingItems = loadAll()
            if let existing = existingItems.first(where: { $0.kind == .youtube && $0.url == url }) {
                os_log(.default, log: Self.log, "YouTube share already queued %{public}@", redactedURL)
                return existing
            }
            let item = PendingShareItem(
                id: UUID(),
                kind: .youtube,
                createdAt: Date(),
                url: url
            )
            var items = existingItems
            items.append(item)
            replaceAll(items)
            os_log(.default, log: Self.log, "Queued YouTube share %{public}@", redactedURL)
            return item
        }
    }

    @discardableResult
    /// Writes binary data to app-group storage and enqueues the resulting file share item.
    public func enqueueFile(
        data: Data,
        filename: String,
        mimeType: String,
        kind: PendingShareKind
    ) -> PendingShareItem? {
        withAccessLock {
            guard hasRequiredStorage(needsFileContainer: true, context: "enqueueFile(data)") else {
                return nil
            }
            let itemId = UUID()
            guard let filePath = writeFile(
                data: data,
                itemId: itemId,
                filename: filename
            ) else {
                return nil
            }
            let item = PendingShareItem(
                id: itemId,
                kind: kind,
                createdAt: Date(),
                filePath: filePath,
                filename: filename,
                mimeType: mimeType
            )
            append(item)
            return item
        }
    }

    @discardableResult
    /// Copies an existing file into app-group storage and enqueues the resulting file share item.
    public func enqueueFile(
        at url: URL,
        filename: String,
        mimeType: String,
        kind: PendingShareKind
    ) -> PendingShareItem? {
        withAccessLock {
            guard hasRequiredStorage(needsFileContainer: true, context: "enqueueFile(url)") else {
                return nil
            }
            let itemId = UUID()
            guard let filePath = copyFile(
                from: url,
                itemId: itemId,
                filename: filename
            ) else {
                return nil
            }
            let item = PendingShareItem(
                id: itemId,
                kind: kind,
                createdAt: Date(),
                filePath: filePath,
                filename: filename,
                mimeType: mimeType
            )
            append(item)
            return item
        }
    }

    /// Loads all currently queued pending share items.
    public func loadAll() -> [PendingShareItem] {
        withAccessLock {
            guard let defaults else { return [] }
            guard let data = defaults.data(forKey: itemsKey) else { return [] }
            let decoder = Self.makeDecoder()
            return (try? decoder.decode([PendingShareItem].self, from: data)) ?? []
        }
    }

    /// Replaces all queued share items with the provided collection.
    public func replaceAll(_ items: [PendingShareItem]) {
        withAccessLock {
            guard let defaults else { return }
            let encoder = Self.makeEncoder()
            if let data = try? encoder.encode(items) {
                defaults.set(data, forKey: itemsKey)
                defaults.synchronize()
                recordDiagnostics(
                    stage: "replace_all",
                    message: "Replaced pending share queue.",
                    metadata: ["count": "\(items.count)"]
                )
            }
        }
    }

    /// Returns and clears all queued share items.
    public func consumeAll() -> [PendingShareItem] {
        withAccessLock {
            let items = loadAll()
            guard !items.isEmpty else { return [] }
            replaceAll([])
            return items
        }
    }

    /// Clears all queued items and removes any staged files from app-group storage.
    public func clearAll() {
        withAccessLock {
            let items = loadAll()
            for item in items {
                guard let fileURL = resolveFileURL(for: item) else { continue }
                try? fileManager.removeItem(at: fileURL)
            }
            if let defaults {
                defaults.removeObject(forKey: itemsKey)
                defaults.synchronize()
            }
            let root = rootDirectory?.appendingPathComponent(directoryName)
            if let root {
                try? fileManager.removeItem(at: root)
            }
        }
    }

    /// Removes queued items matching the provided identifiers.
    public func remove(ids: [UUID]) {
        withAccessLock {
            guard !ids.isEmpty else { return }
            var items = loadAll()
            items.removeAll { ids.contains($0.id) }
            replaceAll(items)
        }
    }

    /// Resolves the absolute file URL for a queued file item when available.
    public func resolveFileURL(for item: PendingShareItem) -> URL? {
        withAccessLock {
            guard let filePath = item.filePath, let baseDirectory = rootDirectory else { return nil }
            return baseDirectory.appendingPathComponent(filePath)
        }
    }

    /// Removes queued items and backing files older than the provided day count.
    public func cleanup(olderThan days: Int) {
        withAccessLock {
            guard days > 0 else { return }
            let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
            var items = loadAll()
            var removedIds: [UUID] = []
            for item in items where item.createdAt < cutoff {
                if let url = resolveFileURL(for: item) {
                    try? fileManager.removeItem(at: url)
                }
                removedIds.append(item.id)
            }
            if !removedIds.isEmpty {
                items.removeAll { removedIds.contains($0.id) }
                replaceAll(items)
            }
            cleanEmptyDirectories()
            cleanOrphanedDirectories(olderThan: cutoff)
        }
    }

    private func append(_ item: PendingShareItem) {
        var items = loadAll()
        items.append(item)
        replaceAll(items)
    }

    private func writeFile(data: Data, itemId: UUID, filename: String) -> String? {
        guard let baseDirectory = rootDirectory else { return nil }
        let safeFilename = sanitizeFilename(filename)
        let relativePath = "\(directoryName)/\(itemId.uuidString)/\(safeFilename)"
        let fileURL = baseDirectory.appendingPathComponent(relativePath)
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL)
            return relativePath
        } catch {
            return nil
        }
    }

    private func copyFile(from url: URL, itemId: UUID, filename: String) -> String? {
        guard let baseDirectory = rootDirectory else { return nil }
        let safeFilename = sanitizeFilename(filename)
        let relativePath = "\(directoryName)/\(itemId.uuidString)/\(safeFilename)"
        let destinationURL = baseDirectory.appendingPathComponent(relativePath)
        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)
            return relativePath
        } catch {
            return nil
        }
    }

    private func cleanEmptyDirectories() {
        guard let baseDirectory = rootDirectory else { return }
        let root = baseDirectory.appendingPathComponent(directoryName)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else { continue }
            if (try? fileManager.contentsOfDirectory(atPath: url.path).isEmpty) == true {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func cleanOrphanedDirectories(olderThan cutoff: Date) {
        guard let baseDirectory = rootDirectory else { return }
        let root = baseDirectory.appendingPathComponent(directoryName)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey]
        ) else {
            return
        }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey]),
                  values.isDirectory == true,
                  let createdAt = values.creationDate,
                  createdAt < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func sanitizeFilename(_ filename: String) -> String {
        let clean = filename.replacingOccurrences(of: "/", with: "_")
        return clean.isEmpty ? "shared_file" : clean
    }

    var defaults: UserDefaults? {
        if let userDefaults { return userDefaults }
        guard allowAppGroupFallback else { return nil }
        guard let suiteName = AppGroupConfiguration.appGroupId else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    var rootDirectory: URL? {
        if let baseDirectory { return baseDirectory }
        guard allowAppGroupFallback else { return nil }
        guard let suiteName = AppGroupConfiguration.appGroupId else { return nil }
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
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
    private func withAccessLock<T>(_ operation: () -> T) -> T {
        accessLock.lock()
        defer { accessLock.unlock() }
        return operation()
    }
}
