import Foundation

@MainActor
public protocol NetworkStatusProviding {
    var isNetworkAvailable: Bool { get }
}

extension ConnectivityMonitor: NetworkStatusProviding {}
