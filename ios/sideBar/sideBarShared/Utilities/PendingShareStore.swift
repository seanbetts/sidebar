import Foundation

public enum PendingShareKind: String, Codable {
    case website
    case file
    case image
    case youtube
}

public struct PendingShareItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public let kind: PendingShareKind
    public let createdAt: Date
    public let url: String?
    public let filePath: String?
    public let filename: String?
    public let mimeType: String?

    public init(
        id: UUID,
        kind: PendingShareKind,
        createdAt: Date,
        url: String? = nil,
        filePath: String? = nil,
        filename: String? = nil,
        mimeType: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.url = url
        self.filePath = filePath
        self.filename = filename
        self.mimeType = mimeType
    }
}

public final class PendingShareStore {
    public static let shared = PendingShareStore()

    private let itemsKey = "pendingShareItems"
    private let directoryName = "pending-shares"
    private let fileManager: FileManager
    private let baseDirectory: URL?
    private let userDefaults: UserDefaults?

    public init(
        baseDirectory: URL? = nil,
        userDefaults: UserDefaults? = nil,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    @discardableResult
    public func enqueueWebsite(url: String) -> PendingShareItem? {
        let item = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: Date(),
            url: url
        )
        append(item)
        return item
    }

    @discardableResult
    public func enqueueYouTube(url: String) -> PendingShareItem? {
        let existingItems = loadAll()
        if let existing = existingItems.first(where: { $0.kind == .youtube && $0.url == url }) {
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
        return item
    }

    @discardableResult
    public func enqueueFile(
        data: Data,
        filename: String,
        mimeType: String,
        kind: PendingShareKind
    ) -> PendingShareItem? {
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

    @discardableResult
    public func enqueueFile(
        at url: URL,
        filename: String,
        mimeType: String,
        kind: PendingShareKind
    ) -> PendingShareItem? {
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

    public func loadAll() -> [PendingShareItem] {
        guard let defaults else { return [] }
        guard let data = defaults.data(forKey: itemsKey) else { return [] }
        let decoder = Self.makeDecoder()
        return (try? decoder.decode([PendingShareItem].self, from: data)) ?? []
    }

    public func replaceAll(_ items: [PendingShareItem]) {
        guard let defaults else { return }
        let encoder = Self.makeEncoder()
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: itemsKey)
            defaults.synchronize()
        }
    }

    public func remove(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var items = loadAll()
        items.removeAll { ids.contains($0.id) }
        replaceAll(items)
    }

    public func resolveFileURL(for item: PendingShareItem) -> URL? {
        guard let filePath = item.filePath, let baseDirectory = rootDirectory else { return nil }
        return baseDirectory.appendingPathComponent(filePath)
    }

    public func cleanup(olderThan days: Int) {
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

    private var defaults: UserDefaults? {
        if let userDefaults { return userDefaults }
        guard let suiteName = AppGroupConfiguration.appGroupId else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    private var rootDirectory: URL? {
        if let baseDirectory { return baseDirectory }
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
}
