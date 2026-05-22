import Foundation

enum SyncHealthState: Equatable {
    case healthy
    case reconnecting
    case degraded
    case offline

    var allowsFallbackPolling: Bool {
        switch self {
        case .degraded, .reconnecting:
            return true
        case .healthy, .offline:
            return false
        }
    }
}

enum SyncHealthModel {
    static func evaluate(
        canAttemptServerRead: Bool,
        realtimeConnected: Bool,
        hasPendingReconnectRefresh: Bool,
        lastRefreshSucceeded: Bool
    ) -> SyncHealthState {
        guard canAttemptServerRead else {
            return .offline
        }
        if hasPendingReconnectRefresh || !lastRefreshSucceeded {
            return .reconnecting
        }
        if !realtimeConnected {
            return .degraded
        }
        return .healthy
    }
}
