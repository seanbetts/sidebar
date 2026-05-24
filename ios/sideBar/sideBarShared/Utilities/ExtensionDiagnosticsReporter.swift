import Foundation
import OSLog

public enum DiagnosticsMetadataSanitizer {
    private static let allowedKeys: Set<String> = [
        "action",
        "app_group_source",
        "app_version",
        "auth_key_present",
        "auth_state",
        "backend_hint",
        "build_number",
        "bundle_id",
        "category",
        "code",
        "content_type",
        "context",
        "count",
        "decode_success",
        "duration_ms",
        "event_type",
        "favicon_count",
        "feature",
        "has_bucket",
        "has_cached_snapshot",
        "has_data_key",
        "has_defaults",
        "has_endpoint",
        "has_public_base",
        "has_root_directory",
        "host",
        "is_authenticated",
        "item_count",
        "item_provider_count",
        "needs_file_container",
        "ok",
        "operation",
        "process_name",
        "provider",
        "reason",
        "recommended_surface",
        "recovery",
        "recovery_outcome",
        "replay_decision",
        "replay_safety",
        "request_kind",
        "retryability",
        "section",
        "selection",
        "selection_kind",
        "source",
        "status_code",
        "surface",
        "total_count",
        "url",
        "url_error_code",
        "widget_kinds"
    ]

    public static func sanitize(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, item in
            let key = normalizeKey(item.key)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false, value.isEmpty == false, allowedKeys.contains(key) else {
                return
            }
            result[key] = value
        }
    }

    private static func normalizeKey(_ rawKey: String) -> String {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        let characters = Array(trimmed)
        var normalized = ""
        normalized.reserveCapacity(characters.count)

        for index in characters.indices {
            let character = characters[index]

            if character.isLetter {
                let shouldInsertUnderscore = character.isUppercase && normalized.isEmpty == false && (
                    characters[index - 1].isLowercase ||
                    characters[index - 1].isNumber ||
                    (characters[index - 1].isUppercase &&
                        index + 1 < characters.count &&
                        characters[index + 1].isLowercase)
                )
                if shouldInsertUnderscore, normalized.last != "_" {
                    normalized.append("_")
                }
                normalized.append(contentsOf: character.lowercased())
                continue
            }

            if character.isNumber {
                normalized.append(character)
                continue
            }

            if normalized.last != "_" {
                normalized.append("_")
            }
        }

        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

public protocol ExtensionDiagnosticsLogging {
    func log(
        level: OSLogType,
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String]
    )
}

public struct ExtensionDiagnosticsReporter {
    private let logger: any ExtensionDiagnosticsLogging
    private let store: (any ExternalSurfaceDiagnosticsRecording)?

    public init(
        logger: any ExtensionDiagnosticsLogging = SystemExtensionDiagnosticsLogger(),
        store: (any ExternalSurfaceDiagnosticsRecording)? = ExternalSurfaceDiagnosticsStore.shared
    ) {
        self.logger = logger
        self.store = store
    }

    public func recordBreadcrumb(
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        let sanitizedMetadata = sanitize(metadata)
        logger.log(
            level: .info,
            surface: surface,
            stage: stage,
            message: message,
            metadata: sanitizedMetadata
        )
        _ = store?.record(
            surface: surface,
            stage: stage,
            message: message,
            metadata: sanitizedMetadata
        )
    }

    public func captureFailure(
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        let sanitizedMetadata = sanitize(metadata)
        logger.log(
            level: .error,
            surface: surface,
            stage: stage,
            message: message,
            metadata: sanitizedMetadata
        )
        _ = store?.record(
            surface: surface,
            stage: stage,
            message: message,
            metadata: sanitizedMetadata
        )
    }

    private func sanitize(_ metadata: [String: String]) -> [String: String] {
        DiagnosticsMetadataSanitizer.sanitize(metadata)
    }
}

public struct SystemExtensionDiagnosticsLogger: ExtensionDiagnosticsLogging {
    private let logger: Logger

    public init(
        subsystem: String = "sideBar",
        category: String = "ExtensionDiagnostics"
    ) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func log(
        level: OSLogType,
        surface: String,
        stage: String,
        message: String,
        metadata: [String: String]
    ) {
        var rendered = "[\(surface)] \(stage): \(message)"
        if metadata.isEmpty == false {
            let metadataSummary = metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            rendered += " | \(metadataSummary)"
        }
        logger.log(level: level, "\(rendered, privacy: .public)")
    }
}
