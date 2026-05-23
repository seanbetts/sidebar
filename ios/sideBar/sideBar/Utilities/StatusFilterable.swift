import Foundation

/// Protocol for items with a status string.
public protocol StatusFilterable {
    var statusValue: String { get }
}

public extension Array where Element: StatusFilterable {
    static var terminalStatuses: Set<String> {
        ["ready", "failed", "canceled"]
    }

    static func normalizedStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isActiveStatus(_ status: String) -> Bool {
        let normalized = normalizedStatus(status)
        return !normalized.isEmpty && !terminalStatuses.contains(normalized)
    }

    var activeItems: [Element] {
        filter { Self.isActiveStatus($0.statusValue) }
    }

    var readyItems: [Element] {
        filter { Self.normalizedStatus($0.statusValue) == "ready" }
    }

    var failedItems: [Element] {
        filter { Self.normalizedStatus($0.statusValue) == "failed" }
    }

    var hasActiveItems: Bool {
        contains { Self.isActiveStatus($0.statusValue) }
    }
}

enum FileJobStatusPolicy {
    static let successfulTerminalStatuses: Set<String> = ["ready", "completed"]
    static let terminalStatuses: Set<String> = [
        "ready",
        "completed",
        "failed",
        "canceled",
        "cancelled"
    ]

    static func normalized(_ status: String?) -> String {
        (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isSuccessfulTerminal(_ status: String?) -> Bool {
        successfulTerminalStatuses.contains(normalized(status))
    }

    static func isTerminal(_ status: String?) -> Bool {
        terminalStatuses.contains(normalized(status))
    }

    static func isActive(_ status: String?) -> Bool {
        let normalizedStatus = normalized(status)
        return !normalizedStatus.isEmpty && !terminalStatuses.contains(normalizedStatus)
    }
}
