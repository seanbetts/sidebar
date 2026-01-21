import Foundation

public enum ExtensionEventType: String, Codable {
    case websiteSaved
}

public struct ExtensionEvent: Codable, Equatable {
    public let type: ExtensionEventType
    public let timestamp: Date
    public let websiteUrl: String?

    public init(type: ExtensionEventType, timestamp: Date = Date(), websiteUrl: String? = nil) {
        self.type = type
        self.timestamp = timestamp
        self.websiteUrl = websiteUrl
    }
}

public final class ExtensionEventStore {
    public static let shared = ExtensionEventStore()
    private let eventsKey = "extensionEvents"

    private init() {
    }

    public func recordWebsiteSaved(url: String?) {
        append(event: ExtensionEvent(type: .websiteSaved, websiteUrl: url))
    }

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
