import Foundation

enum NotesTransitionDebugTrace {
    private static let envKey = "SIDEBAR_NOTES_TRANSITION_DEBUG"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envKey] == "1"
    }

    static func log(_ event: String, details: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let renderedDetails = details()
        let timestamp = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        if renderedDetails.isEmpty {
            print("[NotesTransitionDebug][+\(timestamp)] \(event)")
        } else {
            print("[NotesTransitionDebug][+\(timestamp)] \(event) \(renderedDetails)")
        }
    }

    static func format(_ point: CGPoint?) -> String {
        guard let point else { return "nil" }
        return String(format: "(%.1f,%.1f)", point.x, point.y)
    }

    static func format(_ size: CGSize?) -> String {
        guard let size else { return "nil" }
        return String(format: "(%.1f,%.1f)", size.width, size.height)
    }

    static func format(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(
            format: "(x:%.1f,y:%.1f,w:%.1f,h:%.1f)",
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height
        )
    }

    static func format(_ value: CGFloat?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.1f", value)
    }

    static func format(_ range: NSRange) -> String {
        "{\(range.location),\(range.length)}"
    }
}
