#if os(iOS)
import OSLog
import UIKit

@available(iOS 26.0, *)
enum NotesIOSDebugTrace {
    private static let logger = Logger(subsystem: "sideBar", category: "NotesIOSDebug")

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SIDEBAR_NOTES_IOS_ENTRY_DEBUG"] == "1"
    }

    static func log(
        _ event: String,
        textView: UITextView? = nil,
        extras: [String: String] = [:]
    ) {
        guard isEnabled else { return }

        var components = ["[NotesIOSDebug] \(event)"]
        let sortedExtras = extras.keys.sorted().compactMap { key -> String? in
            guard let value = extras[key] else { return nil }
            return "\(key)=\(value)"
        }
        components.append(contentsOf: sortedExtras)

        if let textView {
            components.append("bounds=\(format(textView.bounds))")
            components.append("contentOffset=\(format(textView.contentOffset))")
            components.append("contentSize=\(format(textView.contentSize))")
            components.append("adjustedContentInset=\(format(textView.adjustedContentInset))")
            components.append("textContainerInset=\(format(textView.textContainerInset))")
            components.append("selectedRange=\(format(textView.selectedRange))")
            if let selectionRect = selectionRect(for: textView) {
                components.append("selectionRect=\(format(selectionRect))")
            } else {
                components.append("selectionRect=nil")
            }
            components.append("isFirstResponder=\(textView.isFirstResponder)")
            components.append("windowIsKey=\(textView.window?.isKeyWindow == true)")
        }

        logger.debug("\(components.joined(separator: " "), privacy: .public)")
    }

    private static func selectionRect(for textView: UITextView) -> CGRect? {
        guard let textView = textView as? UIKitNoteTextEditorSurface.AccessoryTextView else {
            return nil
        }
        return textView.selectionRectInContentCoordinates()
    }

    private static func format(_ point: CGPoint) -> String {
        "{x:\(String(format: "%.2f", point.x)),y:\(String(format: "%.2f", point.y))}"
    }

    private static func format(_ size: CGSize) -> String {
        "{w:\(String(format: "%.2f", size.width)),h:\(String(format: "%.2f", size.height))}"
    }

    private static func format(_ rect: CGRect) -> String {
        let xValue = String(format: "%.2f", rect.origin.x)
        let yValue = String(format: "%.2f", rect.origin.y)
        let width = String(format: "%.2f", rect.size.width)
        let height = String(format: "%.2f", rect.size.height)
        return "{x:\(xValue),y:\(yValue),w:\(width),h:\(height)}"
    }

    private static func format(_ insets: UIEdgeInsets) -> String {
        let top = String(format: "%.2f", insets.top)
        let left = String(format: "%.2f", insets.left)
        let bottom = String(format: "%.2f", insets.bottom)
        let right = String(format: "%.2f", insets.right)
        return "{t:\(top),l:\(left),b:\(bottom),r:\(right)}"
    }

    private static func format(_ range: NSRange) -> String {
        "{loc:\(range.location),len:\(range.length)}"
    }
}
#endif
