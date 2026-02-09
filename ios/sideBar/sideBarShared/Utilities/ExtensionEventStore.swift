import Foundation

/// Represents extension-originated save events consumed by the main app.
public enum ExtensionEventType: String, Codable {
    case websiteSaved
    case fileSaved
    case imageSaved
}

/// Represents a recorded event emitted by share extension flows.
public struct ExtensionEvent: Codable, Equatable {
    /// Event category emitted by the extension.
    public let type: ExtensionEventType
    /// Event timestamp used for ordering and retention.
    public let timestamp: Date
    /// Saved website URL for website event types.
    public let websiteUrl: String?
    /// Saved file identifier for file/image event types.
    public let fileId: String?
    /// Saved filename for file/image event types.
    public let filename: String?

    /// Creates an extension event payload.
    public init(
        type: ExtensionEventType,
        timestamp: Date = Date(),
        websiteUrl: String? = nil,
        fileId: String? = nil,
        filename: String? = nil
    ) {
        self.type = type
        self.timestamp = timestamp
        self.websiteUrl = websiteUrl
        self.fileId = fileId
        self.filename = filename
    }
}

/// Persists extension save events in app-group storage for app-side consumption.
public final class ExtensionEventStore {
    /// Process-wide shared extension event store instance.
    public static let shared = ExtensionEventStore()
    private let eventsKey = "extensionEvents"

    private init() {
    }

    /// Records a website-saved event from the extension.
    public func recordWebsiteSaved(url: String?) {
        append(event: ExtensionEvent(type: .websiteSaved, websiteUrl: url))
    }

    /// Records a file-saved event from the extension.
    public func recordFileSaved(fileId: String, filename: String?) {
        append(event: ExtensionEvent(type: .fileSaved, fileId: fileId, filename: filename))
    }

    /// Records an image-saved event from the extension.
    public func recordImageSaved(fileId: String, filename: String?) {
        append(event: ExtensionEvent(type: .imageSaved, fileId: fileId, filename: filename))
    }

    /// Returns and clears all recorded extension events.
    public func consumeEvents() -> [ExtensionEvent] {
        guard let defaults = userDefaults else {
            return []
        }
        defer {
            defaults.removeObject(forKey: eventsKey)
            defaults.synchronize()
        }
        guard let data = defaults.data(forKey: eventsKey) else { return [] }
        let decoder = Self.makeDecoder()
        return (try? decoder.decode([ExtensionEvent].self, from: data)) ?? []
    }

    private func append(event: ExtensionEvent) {
        guard let defaults = userDefaults else {
            return
        }
        var events = loadEvents(defaults: defaults)
        events.append(event)
        let encoder = Self.makeEncoder()
        if let data = try? encoder.encode(events) {
            defaults.set(data, forKey: eventsKey)
            defaults.synchronize()
        }
    }

    private func loadEvents(defaults: UserDefaults) -> [ExtensionEvent] {
        guard let data = defaults.data(forKey: eventsKey) else { return [] }
        let decoder = Self.makeDecoder()
        return (try? decoder.decode([ExtensionEvent].self, from: data)) ?? []
    }

    private var userDefaults: UserDefaults? {
        guard let suiteName = AppGroupConfiguration.appGroupId else {
            return nil
        }
        return UserDefaults(suiteName: suiteName)
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
