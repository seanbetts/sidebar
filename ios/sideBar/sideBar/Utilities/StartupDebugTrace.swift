import Foundation
import OSLog

enum StartupDebugTrace {
    private static let logger = Logger(subsystem: "sideBar", category: "StartupFlow")

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SIDEBAR_STARTUP_DEBUG"] == "1"
    }

    static func log(_ event: String, details: [String: String] = [:]) {
        guard isEnabled else { return }

        let message = ([event] + details
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" })
            .joined(separator: " ")

        logger.info("\(message, privacy: .public)")
    }
}
