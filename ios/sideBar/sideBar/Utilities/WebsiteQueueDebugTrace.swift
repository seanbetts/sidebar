import Foundation
import OSLog

enum WebsiteQueueDebugTrace {
    static let environmentVariable = "SIDEBAR_WEBSITE_QUEUE_DEBUG"

    private static let logger = Logger(subsystem: "sideBar", category: "WebsiteQueueDebug")

    static var isEnabled: Bool {
        isEnabled(environment: ProcessInfo.processInfo.environment)
    }

    static func isEnabled(environment: [String: String]) -> Bool {
        environment[environmentVariable] == "1"
    }

    static func log(_ event: String, details: [String] = []) {
        guard isEnabled else { return }
        logger.debug("\(render(event: event, details: details, uptime: uptimeString()), privacy: .public)")
    }

    static func measure<T>(_ event: String, details: [String] = [], operation: () -> T) -> T {
        guard isEnabled else {
            return operation()
        }

        let start = ProcessInfo.processInfo.systemUptime
        let result = operation()
        let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
        log(event, details: details + ["elapsed_ms=\(elapsedMs)"])
        return result
    }

    static func render(event: String, details: [String], uptime: String) -> String {
        let prefix = "[WebsiteQueueDebug][+\(uptime)] \(event)"
        guard !details.isEmpty else {
            return prefix
        }
        return "\(prefix) \(details.joined(separator: " "))"
    }

    static func uptimeString(systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> String {
        String(format: "%.3f", systemUptime)
    }
}
