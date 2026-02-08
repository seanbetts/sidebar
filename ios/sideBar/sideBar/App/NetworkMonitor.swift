import Foundation
import Combine
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOffline: Bool = false
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "sidebar.network.monitor")

    init(startMonitoring: Bool = true) {
        monitor = NWPathMonitor()
        if startMonitoring {
            monitor.pathUpdateHandler = { [weak self] path in
                let isOffline = path.status != .satisfied
                Task { @MainActor in
                    self?.isOffline = isOffline
                }
            }
            monitor.start(queue: queue)
        }
    }

    deinit {
        monitor.cancel()
    }
}
