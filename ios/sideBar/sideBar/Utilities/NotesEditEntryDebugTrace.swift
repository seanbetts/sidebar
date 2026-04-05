import Foundation

#if os(iOS)
import UIKit
#endif

enum NotesEditEntryDebugTrace {
    private static let envKey = "SIDEBAR_NOTES_EDIT_ENTRY_DEBUG"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envKey] == "1"
    }

    static func log(_ event: String, details: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let renderedDetails = details()
        let timestamp = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        if renderedDetails.isEmpty {
            print("[NotesEditEntryDebug][+\(timestamp)] \(event)")
        } else {
            print("[NotesEditEntryDebug][+\(timestamp)] \(event) \(renderedDetails)")
        }
    }

    #if os(iOS)
    static func textViewSummary(_ textView: UITextView) -> String {
        let viewportAnchorY: String
        if let editorTextView = textView as? UIKitNoteTextEditorSurface.AccessoryTextView,
           let selectionViewportAnchorY = editorTextView.currentSelectionViewportAnchorY() {
            viewportAnchorY = String(format: "%.2f", selectionViewportAnchorY)
        } else {
            viewportAnchorY = "nil"
        }

        return [
            "isFirstResponder=\(textView.isFirstResponder)",
            "hasWindow=\(textView.window != nil)",
            "contentOffset=(\(String(format: "%.2f", textView.contentOffset.x)),\(String(format: "%.2f", textView.contentOffset.y)))",
            "selectedRange={\(textView.selectedRange.location),\(textView.selectedRange.length)}",
            "viewportAnchorY=\(viewportAnchorY)",
            accessoryTextViewStateSummary(textView),
            adjustedInsetSummary(for: textView)
        ].joined(separator: " ")
    }

    private static func accessoryTextViewStateSummary(_ textView: UITextView) -> String {
        guard let editorTextView = textView as? UIKitNoteTextEditorSurface.AccessoryTextView else {
            return "editorFlags=n/a"
        }
        return [
            "shouldAutofocus=\(editorTextView.shouldAutofocus)",
            "hasScheduledAutofocus=\(editorTextView.hasScheduledAutofocus)",
            "suppressAutofocusReveal=\(editorTextView.suppressAutofocusReveal)"
        ].joined(separator: " ")
    }

    private static func adjustedInsetSummary(for textView: UITextView) -> String {
        "adjustedInset=("
            + "\(String(format: "%.2f", textView.adjustedContentInset.top)),"
            + "\(String(format: "%.2f", textView.adjustedContentInset.left)),"
            + "\(String(format: "%.2f", textView.adjustedContentInset.bottom)),"
            + "\(String(format: "%.2f", textView.adjustedContentInset.right)))"
    }
    #endif
}
