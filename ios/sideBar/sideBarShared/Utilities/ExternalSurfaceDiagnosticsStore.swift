import Foundation

/// Compact app-group-backed diagnostics for widget, share, and extension handoff flows.
public struct ExternalSurfaceDiagnosticEntry: Codable, Equatable {
    public let timestamp: Date
    public let surface: String
    public let stage: String
    public let message: String
    public let metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.surface = surface
        self.stage = stage
        self.message = message
        self.metadata = metadata
    }
}

/// Shared store for recent external-surface diagnostics written into the app group.
public final class ExternalSurfaceDiagnosticsStore {
    public static let shared = ExternalSurfaceDiagnosticsStore()

    private let key = "externalSurfaceDiagnostics"
    private let maxEntries = 200

    private init() {}

    public func record(
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        append(
            ExternalSurfaceDiagnosticEntry(
                surface: surface,
                stage: stage,
                message: message,
                metadata: sanitize(metadata)
            )
        )
    }

    public func recentEntries(limit: Int = 50) -> [ExternalSurfaceDiagnosticEntry] {
        guard let defaults = userDefaults else { return [] }
        let entries = loadEntries(defaults: defaults)
        guard limit > 0 else { return entries }
        return Array(entries.suffix(limit))
    }

    public func exportText(limit: Int = 100) -> String {
        let entries = recentEntries(limit: limit)
        guard !entries.isEmpty else { return "" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return entries.map { entry in
            var line = "\(formatter.string(from: entry.timestamp)) [\(entry.surface)] \(entry.stage): \(entry.message)"
            if !entry.metadata.isEmpty {
                let metadataSummary = entry.metadata
                    .sorted(by: { $0.key < $1.key })
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: " ")
                line += " | \(metadataSummary)"
            }
            return line
        }
        .joined(separator: "\n")
    }

    public func clear() {
        guard let defaults = userDefaults else { return }
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }

    private func append(_ entry: ExternalSurfaceDiagnosticEntry) {
        guard let defaults = userDefaults else { return }
        var entries = loadEntries(defaults: defaults)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: key)
            defaults.synchronize()
        }
    }

    private func loadEntries(defaults: UserDefaults) -> [ExternalSurfaceDiagnosticEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ExternalSurfaceDiagnosticEntry].self, from: data)) ?? []
    }

    private var userDefaults: UserDefaults? {
        guard let suiteName = AppGroupConfiguration.appGroupId else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    private func sanitize(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, item in
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            result[item.key] = value
        }
    }
}
