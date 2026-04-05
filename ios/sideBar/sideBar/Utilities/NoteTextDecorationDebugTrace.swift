import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum NoteTextDecorationDebugTrace {
    private static let envKey = "SIDEBAR_NOTE_DECORATION_DEBUG"
    private static var lastDetailsByEvent: [String: String] = [:]
    private static var suppressedCountByEvent: [String: Int] = [:]

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envKey] == "1"
    }

    static func log(
        _ event: String,
        details: @autoclosure () -> String = "",
        dedupe: Bool = false
    ) {
        guard isEnabled else { return }
        let renderedDetails = details()
        if dedupe, lastDetailsByEvent[event] == renderedDetails {
            suppressedCountByEvent[event, default: 0] += 1
            return
        }

        if dedupe, let suppressedCount = suppressedCountByEvent[event], suppressedCount > 0 {
            suppressedCountByEvent[event] = nil
            emit("\(event).suppressed", details: "duplicates=\(suppressedCount)")
        }

        if dedupe {
            lastDetailsByEvent[event] = renderedDetails
        }

        emit(event, details: renderedDetails)
    }

    private static func emit(_ event: String, details: String) {
        let timestamp = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        if details.isEmpty {
            print("[NoteDecorationDebug][+\(timestamp)] \(event)")
        } else {
            print("[NoteDecorationDebug][+\(timestamp)] \(event) \(details)")
        }
    }

    static func summarizeRects(_ rects: [CGRect], label: String) -> String {
        let head = rects.prefix(3).enumerated().map { index, rect in
            "\(label)\(index)=\(summarize(rect))"
        }
        let suffix = rects.count > 3 ? " \(label)Count=\(rects.count)" : " \(label)Count=\(rects.count)"
        return head.joined(separator: " ") + suffix
    }

    static func summarize(_ rect: CGRect) -> String {
        "(\(rounded(rect.minX)),\(rounded(rect.minY)),\(rounded(rect.width)),\(rounded(rect.height)))"
    }

    static func summarize(_ point: CGPoint) -> String {
        "(\(rounded(point.x)),\(rounded(point.y)))"
    }

    #if canImport(UIKit)
    static func summarize(_ insets: UIEdgeInsets) -> String {
        "(t:\(rounded(insets.top)),l:\(rounded(insets.left)),b:\(rounded(insets.bottom)),r:\(rounded(insets.right)))"
    }

    static func summarize(_ size: CGSize) -> String {
        "(\(rounded(size.width)),\(rounded(size.height)))"
    }
    #endif

    private static func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
