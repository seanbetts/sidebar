import Foundation

@MainActor
public protocol NetworkStatusProviding {
    var isNetworkAvailable: Bool { get }
    var isOffline: Bool { get }
}

extension ConnectivityMonitor: NetworkStatusProviding {}
