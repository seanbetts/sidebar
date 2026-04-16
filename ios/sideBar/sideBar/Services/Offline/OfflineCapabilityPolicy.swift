import Foundation

struct OfflineCapabilityPolicy: Equatable, Sendable {
    let isOffline: Bool
    let isNetworkAvailable: Bool
    let isServerReachable: Bool

    var canReadLocal: Bool { true }

    var canAttemptServerRead: Bool {
        isNetworkAvailable && isServerReachable && !isOffline
    }

    var canAttemptServerWrite: Bool {
        canAttemptServerRead
    }

    var shouldQueueWrites: Bool {
        !canAttemptServerWrite
    }
}

extension NetworkStatusProviding {
    var offlineCapabilityPolicy: OfflineCapabilityPolicy {
        OfflineCapabilityPolicy(
            isOffline: isOffline,
            isNetworkAvailable: isNetworkAvailable,
            isServerReachable: isServerReachable
        )
    }
}
