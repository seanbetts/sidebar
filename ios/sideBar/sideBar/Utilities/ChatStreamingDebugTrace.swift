import Foundation
import sideBarShared

enum ChatStreamingDebugTrace {
    private static let envKey = "SIDEBAR_CHAT_STREAM_DEBUG"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envKey] == "1"
    }

    static func log(_ event: String, details: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let renderedDetails = details()
        let timestamp = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        if renderedDetails.isEmpty {
            print("[ChatStreamDebug][+\(timestamp)] \(event)")
        } else {
            print("[ChatStreamDebug][+\(timestamp)] \(event) \(renderedDetails)")
        }
    }

    static func shortID(_ id: String?) -> String {
        guard let id, !id.isEmpty else {
            return "nil"
        }
        return String(id.prefix(8))
    }

    static func summarizeMessage(_ message: Message?) -> String {
        guard let message else {
            return "message=nil"
        }
        return [
            "message=\(shortID(message.id))",
            "role=\(message.role.rawValue)",
            "status=\(message.status.rawValue)",
            "contentChars=\(message.content.count)",
            "toolCalls=\(message.toolCalls?.count ?? 0)",
            "needsNewline=\(message.needsNewline?.description ?? "nil")",
            "error=\((message.error?.trimmedOrNil) != nil)"
        ].joined(separator: " ")
    }

    static func summarizeEventTypes(_ events: [ChatStreamEvent]) -> String {
        guard !events.isEmpty else {
            return "none"
        }
        let counts = events.reduce(into: [String: Int]()) { partialResult, event in
            partialResult[event.type.rawValue, default: 0] += 1
        }
        return counts.keys.sorted().map { key in
            "\(key)=\(counts[key] ?? 0)"
        }
        .joined(separator: ",")
    }
}
