import Foundation

@MainActor
public protocol NetworkStatusProviding {
    var isNetworkAvailable: Bool { get }
    var isOffline: Bool { get }
    var isServerReachable: Bool { get }
}

extension ConnectivityMonitor: NetworkStatusProviding {}

public extension NetworkStatusProviding {
    var isServerReachable: Bool { true }
}
