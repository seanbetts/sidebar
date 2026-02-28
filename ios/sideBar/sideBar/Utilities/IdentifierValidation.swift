import Foundation

/// Lightweight identifier validation utilities for client-side routing and API guards.
enum IdentifierValidation {
    /// Returns true when a value is a canonical UUID string accepted by backend endpoints.
    static func isUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    /// Returns true for IDs that represent client-only local placeholders.
    static func isLocalPlaceholderID(_ value: String) -> Bool {
        value.hasPrefix("local-") || value.hasPrefix("youtube-")
    }

    /// Returns true when an ingestion identifier can be sent to server file endpoints.
    static func isServerFileID(_ value: String) -> Bool {
        isUUID(value)
    }

    /// Returns true when a task identifier can be sent to server task endpoints.
    static func isServerTaskID(_ value: String) -> Bool {
        isUUID(value)
    }
}
