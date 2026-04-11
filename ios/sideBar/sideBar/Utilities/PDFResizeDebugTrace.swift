import CoreGraphics
import Foundation

enum PDFResizeDebugTrace {
    private static let envKey = "SIDEBAR_PDF_RESIZE_DEBUG"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envKey] == "1"
    }

    static func log(_ event: String, details: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let renderedDetails = details()
        let timestamp = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        if renderedDetails.isEmpty {
            print("[PDFResizeDebug][+\(timestamp)] \(event)")
        } else {
            print("[PDFResizeDebug][+\(timestamp)] \(event) \(renderedDetails)")
        }
    }

    static func describe(_ size: CGSize) -> String {
        "(\(rounded(size.width)), \(rounded(size.height)))"
    }

    static func describe(_ point: CGPoint) -> String {
        "(\(rounded(point.x)), \(rounded(point.y)))"
    }

    static func describe(_ rect: CGRect) -> String {
        "origin=(\(rounded(rect.origin.x)), \(rounded(rect.origin.y))) size=\(describe(rect.size))"
    }

    static func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
