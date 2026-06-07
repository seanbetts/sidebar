import Foundation
import os

/// Redacted authentication diagnostic event.
public struct AuthDiagnosticsEvent: Equatable, Sendable {
    public let name: String
    public let metadata: [String: String]

    public init(name: String, metadata: [String: String] = [:]) {
        self.name = Self.allowedNames.contains(name) ? name : "unknown"
        self.metadata = Self.sanitizedMetadata(metadata)
    }

    private static let allowedNames: Set<String> = [
        "backend_rejection_accepted",
        "backend_rejection_ignored",
        "offline_access_window"
    ]
    private static let allowedReasons: Set<String> = [
        "current_token",
        "legacy_timestamp_seeded",
        "missing_timestamp_after_migration",
        "missing_timestamp_without_token",
        "outside_window",
        "previous_token",
        "unscoped",
        "within_window",
        "unknown"
    ]
    private static let allowedAuthStates: Set<String> = [
        AuthState.signedOut.rawValue,
        AuthState.active.rawValue,
        AuthState.staleRecoverable.rawValue,
        AuthState.reauthenticationRequired.rawValue
    ]

    private static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        if let reason = metadata["reason"] {
            sanitized["reason"] = allowedReasons.contains(reason) ? reason : "unknown"
        }
        if let authState = metadata["auth_state"], allowedAuthStates.contains(authState) {
            sanitized["auth_state"] = authState
        }
        return sanitized
    }
}

/// Records redacted authentication diagnostics.
public protocol AuthDiagnosticsRecording: Sendable {
    func record(_ event: AuthDiagnosticsEvent)
}

/// Logs redacted authentication diagnostics through unified logging.
public struct LoggingAuthDiagnosticsRecorder: AuthDiagnosticsRecording {
    private let logger = Logger(subsystem: "sideBar", category: "AuthDiagnostics")

    public init() {}

    public func record(_ event: AuthDiagnosticsEvent) {
        let metadata = event.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        logger.notice("auth_diagnostic name=\(event.name, privacy: .public) metadata=\(metadata, privacy: .public)")
    }
}
