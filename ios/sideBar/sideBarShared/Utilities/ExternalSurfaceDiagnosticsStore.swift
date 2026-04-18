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

public protocol ExternalSurfaceDiagnosticsRecording {
    @discardableResult
    func record(
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String]
    ) -> Bool
}

/// Shared store for recent external-surface diagnostics written into the app group.
public final class ExternalSurfaceDiagnosticsStore: ExternalSurfaceDiagnosticsRecording {
    public static let shared = ExternalSurfaceDiagnosticsStore()

    private let key = "externalSurfaceDiagnostics"
    private let maxEntries = 200
    private let stateLock = NSLock()
    private var cachedEntries: [ExternalSurfaceDiagnosticEntry]?

    private init() {}

    @discardableResult
    public func record(
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String] = [:]
    ) -> Bool {
        append(
            ExternalSurfaceDiagnosticEntry(
                surface: surface,
                stage: stage,
                message: message,
                metadata: sanitize(defaultMetadata().merging(metadata, uniquingKeysWith: { _, new in new }))
            )
        )
    }

    public func recentEntries(limit: Int = 50) -> [ExternalSurfaceDiagnosticEntry] {
        let entries = loadEntries()
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
        stateLock.lock()
        cachedEntries = []
        stateLock.unlock()
        guard let defaults = userDefaults else { return }
        defaults.removeObject(forKey: key)
    }

    private func append(_ entry: ExternalSurfaceDiagnosticEntry) -> Bool {
        var entries = loadEntries()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        stateLock.lock()
        cachedEntries = entries
        stateLock.unlock()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let defaults = userDefaults,
              let data = try? encoder.encode(entries) else {
            return false
        }
        defaults.set(data, forKey: key)
        return true
    }

    private func loadEntries() -> [ExternalSurfaceDiagnosticEntry] {
        stateLock.lock()
        if let cachedEntries {
            stateLock.unlock()
            return cachedEntries
        }
        stateLock.unlock()

        guard let defaults = userDefaults,
              let data = defaults.data(forKey: key) else {
            stateLock.lock()
            cachedEntries = []
            stateLock.unlock()
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([ExternalSurfaceDiagnosticEntry].self, from: data)) ?? []
        stateLock.lock()
        cachedEntries = decoded
        stateLock.unlock()
        return decoded
    }

    private var userDefaults: UserDefaults? {
        guard let suiteName = AppGroupConfiguration.appGroupId else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    private func sanitize(_ metadata: [String: String]) -> [String: String] {
        DiagnosticsMetadataSanitizer.sanitize(metadata)
    }

    private func defaultMetadata() -> [String: String] {
        let mainBundle = Bundle.main
        return [
            "bundle_id": nonEmpty(
                mainBundle.bundleIdentifier,
                fallback: "unknown.bundle"
            ),
            "bundle_path": nonEmpty(
                mainBundle.bundleURL.path,
                fallback: "unknown.bundle_path"
            ),
            "app_version": nonEmpty(
                mainBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                fallback: "0"
            ),
            "build_number": nonEmpty(
                mainBundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
                fallback: "0"
            ),
            "process_name": nonEmpty(
                ProcessInfo.processInfo.processName,
                fallback: "unknown_process"
            ),
            "process_id": "\(ProcessInfo.processInfo.processIdentifier)"
        ]
    }

    private func nonEmpty(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
