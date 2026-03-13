import Foundation

/// Represents transcript metadata for a saved website.
public struct WebsiteTranscriptEntry: Codable, Equatable {
    public let status: String?
    public let fileId: String?
    public let updatedAt: String?
    public let error: String?

    public init(
        status: String? = nil,
        fileId: String? = nil,
        updatedAt: String? = nil,
        error: String? = nil
    ) {
        self.status = status
        self.fileId = fileId
        self.updatedAt = updatedAt
        self.error = error
    }
}

/// Represents extension-originated save events consumed by the main app.
public enum ExtensionEventType: String, Codable {
    case websiteSaved
    case fileSaved
    case imageSaved
}

/// Canonical website payload emitted by extension save flows.
public struct ExtensionSavedWebsite: Codable, Equatable {
    private static let minimalTitleLength = 256

    public let id: String
    public let title: String
    public let url: String
    public let urlFull: String?
    public let domain: String
    public let content: String?
    public let source: String?
    public let savedAt: String?
    public let publishedAt: String?
    public let pinned: Bool
    public let pinnedOrder: Int?
    public let archived: Bool
    public let faviconUrl: String?
    public let faviconR2Key: String?
    public let youtubeTranscripts: [String: WebsiteTranscriptEntry]?
    public let readingTime: String?
    public let updatedAt: String?
    public let lastOpenedAt: String?
    public let requiresDetailFetch: Bool

    public init(
        id: String,
        title: String,
        url: String,
        urlFull: String? = nil,
        domain: String,
        content: String? = nil,
        source: String? = nil,
        savedAt: String? = nil,
        publishedAt: String? = nil,
        pinned: Bool = false,
        pinnedOrder: Int? = nil,
        archived: Bool = false,
        faviconUrl: String? = nil,
        faviconR2Key: String? = nil,
        youtubeTranscripts: [String: WebsiteTranscriptEntry]? = nil,
        readingTime: String? = nil,
        updatedAt: String? = nil,
        lastOpenedAt: String? = nil,
        requiresDetailFetch: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.urlFull = urlFull
        self.domain = domain
        self.content = content
        self.source = source
        self.savedAt = savedAt
        self.publishedAt = publishedAt
        self.pinned = pinned
        self.pinnedOrder = pinnedOrder
        self.archived = archived
        self.faviconUrl = faviconUrl
        self.faviconR2Key = faviconR2Key
        self.youtubeTranscripts = youtubeTranscripts
        self.readingTime = readingTime
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.requiresDetailFetch = requiresDetailFetch
    }

    public func compactForDeferredHydration() -> ExtensionSavedWebsite {
        ExtensionSavedWebsite(
            id: id,
            title: title,
            url: url,
            urlFull: urlFull,
            domain: domain,
            content: nil,
            source: source,
            savedAt: savedAt,
            publishedAt: publishedAt,
            pinned: pinned,
            pinnedOrder: pinnedOrder,
            archived: archived,
            faviconUrl: faviconUrl,
            faviconR2Key: faviconR2Key,
            youtubeTranscripts: youtubeTranscripts,
            readingTime: readingTime,
            updatedAt: updatedAt,
            lastOpenedAt: lastOpenedAt,
            requiresDetailFetch: true
        )
    }

    public func minimalForDeferredHydration() -> ExtensionSavedWebsite {
        ExtensionSavedWebsite(
            id: id,
            title: String(title.prefix(Self.minimalTitleLength)),
            url: url,
            urlFull: nil,
            domain: domain,
            content: nil,
            source: nil,
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: nil,
            lastOpenedAt: nil,
            requiresDetailFetch: true
        )
    }
}

/// Represents a recorded event emitted by share extension flows.
public struct ExtensionEvent: Codable, Equatable {
    /// Event category emitted by the extension.
    public let type: ExtensionEventType
    /// Event timestamp used for ordering and retention.
    public let timestamp: Date
    /// Saved website URL for website event types.
    public let websiteUrl: String?
    /// Saved website detail for direct-save website events.
    public let website: ExtensionSavedWebsite?
    /// Saved file identifier for file/image event types.
    public let fileId: String?
    /// Saved filename for file/image event types.
    public let filename: String?

    /// Creates an extension event payload.
    public init(
        type: ExtensionEventType,
        timestamp: Date = Date(),
        websiteUrl: String? = nil,
        website: ExtensionSavedWebsite? = nil,
        fileId: String? = nil,
        filename: String? = nil
    ) {
        self.type = type
        self.timestamp = timestamp
        self.websiteUrl = websiteUrl
        self.website = website
        self.fileId = fileId
        self.filename = filename
    }
}

/// Persists extension save events in app-group storage for app-side consumption.
public final class ExtensionEventStore {
    /// Process-wide shared extension event store instance.
    public static let shared = ExtensionEventStore()
    private let eventsKey = "extensionEvents"
    private let maxStoredEventsBytes = 240_000
    private let injectedUserDefaults: UserDefaults?

    public init(userDefaults: UserDefaults? = nil) {
        self.injectedUserDefaults = userDefaults
    }

    /// Records a website-saved event from the extension.
    public func recordWebsiteSaved(url: String?) {
        append(event: ExtensionEvent(type: .websiteSaved, websiteUrl: url))
    }

    /// Records a website-saved event with canonical detail from the extension.
    public func recordWebsiteSaved(website: ExtensionSavedWebsite) {
        append(event: ExtensionEvent(type: .websiteSaved, websiteUrl: website.url, website: website))
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
            recordDiagnostics(
                stage: "consume_events_missing_store",
                message: "Extension events unavailable because shared defaults could not be opened."
            )
            return []
        }
        defer {
            defaults.removeObject(forKey: eventsKey)
            defaults.synchronize()
        }
        guard let data = defaults.data(forKey: eventsKey) else {
            recordDiagnostics(
                stage: "consume_events_empty",
                message: "No extension events were queued."
            )
            return []
        }
        let decoder = Self.makeDecoder()
        let events = (try? decoder.decode([ExtensionEvent].self, from: data)) ?? []
        recordDiagnostics(
            stage: "consume_events",
            message: "Consumed extension events.",
            metadata: [
                "count": "\(events.count)",
                "suite": AppGroupConfiguration.appGroupId ?? "nil"
            ]
        )
        return events
    }

    /// Clears all recorded extension events without consuming them.
    public func clear() {
        guard let defaults = userDefaults else { return }
        defaults.removeObject(forKey: eventsKey)
        defaults.synchronize()
        recordDiagnostics(
            stage: "clear_events",
            message: "Cleared extension events."
        )
    }

    private func append(event: ExtensionEvent) {
        guard let defaults = userDefaults else {
            recordDiagnostics(
                stage: "append_event_missing_store",
                message: "Could not append extension event because shared defaults could not be opened.",
                metadata: [
                    "event_type": event.type.rawValue
                ]
            )
            return
        }
        var events = loadEvents(defaults: defaults)
        guard let storedEvent = normalizedEventForStorage(event, existingEvents: events) else {
            recordDiagnostics(
                stage: "append_event_dropped",
                message: "Dropped extension event because it exceeded shared storage limits.",
                metadata: [
                    "event_type": event.type.rawValue
                ]
            )
            return
        }
        events.append(storedEvent)
        let encoder = Self.makeEncoder()
        if let data = try? encoder.encode(events) {
            defaults.set(data, forKey: eventsKey)
            defaults.synchronize()
            recordDiagnostics(
                stage: "append_event",
                message: "Recorded extension event.",
                metadata: [
                    "event_type": storedEvent.type.rawValue,
                    "count": "\(events.count)",
                    "suite": AppGroupConfiguration.appGroupId ?? "nil"
                ]
            )
        }
    }

    private func loadEvents(defaults: UserDefaults) -> [ExtensionEvent] {
        guard let data = defaults.data(forKey: eventsKey) else { return [] }
        let decoder = Self.makeDecoder()
        return (try? decoder.decode([ExtensionEvent].self, from: data)) ?? []
    }

    private func normalizedEventForStorage(
        _ event: ExtensionEvent,
        existingEvents: [ExtensionEvent]
    ) -> ExtensionEvent? {
        let candidates: [ExtensionEvent]
        if let website = event.website {
            candidates = [
                event,
                ExtensionEvent(
                    type: event.type,
                    timestamp: event.timestamp,
                    websiteUrl: event.websiteUrl,
                    website: website.compactForDeferredHydration(),
                    fileId: event.fileId,
                    filename: event.filename
                ),
                ExtensionEvent(
                    type: event.type,
                    timestamp: event.timestamp,
                    websiteUrl: event.websiteUrl,
                    website: website.minimalForDeferredHydration(),
                    fileId: event.fileId,
                    filename: event.filename
                )
            ]
        } else {
            candidates = [event]
        }

        let encoder = Self.makeEncoder()
        for candidate in candidates {
            let payload = existingEvents + [candidate]
            guard let data = try? encoder.encode(payload) else {
                continue
            }
            if data.count <= maxStoredEventsBytes {
                return candidate
            }
        }
        return nil
    }

    private var userDefaults: UserDefaults? {
        if let injectedUserDefaults {
            return injectedUserDefaults
        }
        guard let suiteName = AppGroupConfiguration.appGroupId else {
            return nil
        }
        return UserDefaults(suiteName: suiteName)
    }

    private func recordDiagnostics(
        stage: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "extension_events",
            stage: stage,
            message: message,
            metadata: metadata.merging(
                [
                    "bundle_id": Bundle.main.bundleIdentifier ?? "nil"
                ],
                uniquingKeysWith: { current, _ in current }
            )
        )
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
