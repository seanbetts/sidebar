import Foundation
import Combine
import Network

final class NetworkMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var isOffline: Bool = false
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "sidebar.network.monitor")

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            DispatchQueue.main.async {
                self?.isOffline = isOffline
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
