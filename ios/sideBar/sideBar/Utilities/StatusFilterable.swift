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
