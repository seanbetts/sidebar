import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)

@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownTextView: NSViewRepresentable {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var isEditable: Bool = true
    var isSelectable: Bool = true
    var syncSelection: Bool = true
    var isScrollEnabled: Bool = true
    var onTap: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.allowsImageEditing = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textStorage?.setAttributedString(displayText(for: text, isEditable: isEditable))
        textView.refreshTypingAttributesForSelection()
        let tap = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        textView.addGestureRecognizer(tap)
        context.coordinator.tapRecognizer = tap

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = isScrollEnabled
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        scrollView.hasVerticalScroller = isScrollEnabled
        context.coordinator.tapRecognizer?.isEnabled = onTap != nil
        let nsText = displayText(for: text, isEditable: isEditable)
        let didReplaceText = !(textView.attributedString().isEqual(to: nsText))
        if didReplaceText {
            textView.textStorage?.setAttributedString(nsText)
            textView.needsDisplay = true
        }
        if syncSelection {
            let desiredRange = nsRange(from: selection, in: text)
            if context.coordinator.shouldApplyDesiredSelection(
                desiredRange: desiredRange,
                currentRange: textView.selectedRange(),
                hasFirstResponder: textView.window?.firstResponder === textView,
                didReplaceText: didReplaceText
            ) {
                textView.setSelectedRange(desiredRange)
                context.coordinator.lastSelectionReportedByAppKit = desiredRange
            }
        }
        if let markdownTextView = textView as? MarkdownTextView {
            markdownTextView.refreshTypingAttributesForSelection()
        }
        context.coordinator.isUpdating = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMarkdownTextView
        var isUpdating = false
        var tapRecognizer: NSClickGestureRecognizer?
        var lastSelectionReportedByAppKit: NSRange?

        init(_ parent: NativeMarkdownTextView) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap?()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            let snapshot = AttributedString(textView.attributedString())
            if parent.text != snapshot {
                parent.text = snapshot
            }
            if parent.syncSelection {
                lastSelectionReportedByAppKit = textView.selectedRange()
                parent.selection = selectionFromRange(textView.selectedRange(), in: snapshot)
            }
            if let markdownTextView = textView as? MarkdownTextView {
                markdownTextView.refreshTypingAttributesForSelection()
            }
            textView.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            guard parent.syncSelection else { return }
            let snapshot = AttributedString(textView.attributedString())
            if parent.text != snapshot {
                parent.text = snapshot
            }
            lastSelectionReportedByAppKit = textView.selectedRange()
            parent.selection = selectionFromRange(textView.selectedRange(), in: snapshot)
            if let markdownTextView = textView as? MarkdownTextView {
                markdownTextView.refreshTypingAttributesForSelection()
            }
            textView.needsDisplay = true
        }

        func shouldApplyDesiredSelection(
            desiredRange: NSRange,
            currentRange: NSRange,
            hasFirstResponder: Bool,
            didReplaceText: Bool
        ) -> Bool {
            guard desiredRange != currentRange else { return false }
            guard hasFirstResponder else { return true }
            guard didReplaceText else { return false }
            guard let lastSelectionReportedByAppKit else { return true }
            return desiredRange == lastSelectionReportedByAppKit
        }
    }
}

#endif
