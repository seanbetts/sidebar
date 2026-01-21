import Foundation

/// Protocol for items with a status string.
public protocol StatusFilterable {
    var statusValue: String { get }
}

public extension Array where Element: StatusFilterable {
    static var terminalStatuses: [String] {
        ["ready", "failed", "canceled"]
    }

    var activeItems: [Element] {
        filter { !Self.terminalStatuses.contains($0.statusValue) }
    }

    var readyItems: [Element] {
        filter { $0.statusValue == "ready" }
    }

    var failedItems: [Element] {
        filter { $0.statusValue == "failed" }
    }

    var hasActiveItems: Bool {
        contains { !$0.statusValue.isEmpty && !Self.terminalStatuses.contains($0.statusValue) }
    }
}
