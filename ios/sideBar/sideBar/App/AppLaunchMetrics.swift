import Foundation
import os

#if os(iOS)
@MainActor
final class AppLaunchMetrics {
    static let shared = AppLaunchMetrics()

    private let start = CFAbsoluteTimeGetCurrent()
    private let logger = Logger(subsystem: "sideBar", category: "Startup")

    func mark(_ label: String) {
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        logger.info("\(label, privacy: .public) at +\(elapsedMs, privacy: .public)ms")
    }
}
#endif
