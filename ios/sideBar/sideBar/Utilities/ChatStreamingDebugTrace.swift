import Foundation
import sideBarShared

enum ChatStreamingDebugTrace {
    static let environmentVariable = "SIDEBAR_CHAT_STREAM_DEBUG"

    static var isEnabled: Bool {
        isEnabled(environment: ProcessInfo.processInfo.environment)
    }

    static func isEnabled(environment: [String: String]) -> Bool {
        environment[environmentVariable] == "1"
    }

    static func render(event: String, details: [String], uptime: String) -> String {
        let renderedDetails = details.joined(separator: " ")
        if renderedDetails.isEmpty {
            return "[ChatStreamDebug][+\(uptime)] \(event)"
        }
        return "[ChatStreamDebug][+\(uptime)] \(event) \(renderedDetails)"
    }

    static func visibleWhitespacePreview(_ text: String, limit: Int = 160) -> String {
        let escaped = text.unicodeScalars.reduce(into: "") { rendered, scalar in
            switch scalar {
            case "\n":
                rendered += "\\n"
            case "\r":
                rendered += "\\r"
            case "\t":
                rendered += "\\t"
            default:
                rendered.append(String(scalar))
            }
        }
        guard escaped.count > limit else {
            return escaped
        }
        let endIndex = escaped.index(escaped.startIndex, offsetBy: limit)
        return "\(escaped[..<endIndex])..."
    }

    static func log(_ event: String, details: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let timestamp = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        let renderedDetails = details()
        let detailsParts = renderedDetails.isEmpty ? [] : [renderedDetails]
        print(render(event: event, details: detailsParts, uptime: timestamp))
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
            "content=\"\(visibleWhitespacePreview(message.content, limit: 120))\"",
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
