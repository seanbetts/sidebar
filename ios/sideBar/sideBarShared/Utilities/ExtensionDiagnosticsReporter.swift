import Foundation
import OSLog

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
        metadata.reduce(into: [:]) { result, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false, value.isEmpty == false else { return }
            result[key] = value
        }
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
