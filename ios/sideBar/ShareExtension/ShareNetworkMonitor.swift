import Foundation
import Network

enum ShareNetworkMonitor {
    static func isOnline(timeout: TimeInterval = 0.3) async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "sideBar.share.network")
            var didResume = false
            func finish(_ value: Bool) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
                monitor.cancel()
            }
            monitor.pathUpdateHandler = { path in
                finish(path.status == .satisfied)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(true)
            }
        }
    }
}
