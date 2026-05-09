import Foundation
import OSLog
import sideBarShared

enum ChatStreamDebugTrace {
    static let environmentVariable = "SIDEBAR_CHAT_STREAM_DEBUG"

    private static let logger = Logger(subsystem: "sideBar", category: "ChatStreamDebug")

    static var isEnabled: Bool {
        isEnabled(environment: ProcessInfo.processInfo.environment)
            || UserDefaults.standard.bool(forKey: environmentVariable)
    }

    static func isEnabled(environment: [String: String]) -> Bool {
        environment[environmentVariable] == "1"
    }

    static func log(_ event: String, details: [String] = []) {
        guard isEnabled else { return }
        logger.debug("\(render(event: event, details: details), privacy: .public)")
    }

    static func payloadKeys(_ data: AnyCodable?) -> String {
        guard let payload = data?.value as? [String: Any] else {
            return "none"
        }
        return payload.keys.sorted().joined(separator: ",")
    }

    static func render(event: String, details: [String]) -> String {
        let prefix = "[ChatStreamDebug] \(event)"
        guard !details.isEmpty else {
            return prefix
        }
        return "\(prefix) \(details.joined(separator: " "))"
    }
}
