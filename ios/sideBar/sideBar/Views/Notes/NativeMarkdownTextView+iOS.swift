import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)

@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownTextView: UIViewRepresentable {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var isEditable: Bool = true
    var isSelectable: Bool = true
    var syncSelection: Bool = true
    var isScrollEnabled: Bool = true
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.allowsEditingTextAttributes = true
        textView.isScrollEnabled = isScrollEnabled
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = displayText(for: text, isEditable: isEditable)
        textView.refreshTypingAttributesForSelection()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)
        context.coordinator.tapRecognizer = tap
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.isScrollEnabled = isScrollEnabled
        context.coordinator.tapRecognizer?.isEnabled = onTap != nil
        let nsText = displayText(for: text, isEditable: isEditable)
        let didReplaceText = !textView.attributedText.isEqual(to: nsText)
        if didReplaceText {
            textView.attributedText = nsText
            textView.setNeedsDisplay()
        }
        if syncSelection {
            let desiredRange = nsRange(from: selection, in: text)
            if context.coordinator.shouldApplyDesiredSelection(
                desiredRange: desiredRange,
                currentRange: textView.selectedRange,
                isFirstResponder: textView.isFirstResponder,
                didReplaceText: didReplaceText
            ) {
                textView.selectedRange = desiredRange
                context.coordinator.lastSelectionReportedByUIKit = desiredRange
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

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeMarkdownTextView
        var isUpdating = false
        var tapRecognizer: UITapGestureRecognizer?
        var lastSelectionReportedByUIKit: NSRange?

        init(_ parent: NativeMarkdownTextView) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap?()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            let snapshot = AttributedString(textView.attributedText)
            if parent.text != snapshot {
                parent.text = snapshot
            }
            if parent.syncSelection {
                lastSelectionReportedByUIKit = textView.selectedRange
                parent.selection = selectionFromRange(textView.selectedRange, in: snapshot)
            }
            if let markdownTextView = textView as? MarkdownTextView {
                markdownTextView.refreshTypingAttributesForSelection()
            }
            textView.setNeedsDisplay()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating else { return }
            guard parent.syncSelection else { return }
            let snapshot = AttributedString(textView.attributedText)
            if parent.text != snapshot {
                parent.text = snapshot
            }
            lastSelectionReportedByUIKit = textView.selectedRange
            parent.selection = selectionFromRange(textView.selectedRange, in: snapshot)
            if let markdownTextView = textView as? MarkdownTextView {
                markdownTextView.refreshTypingAttributesForSelection()
            }
            textView.setNeedsDisplay()
        }

        func shouldApplyDesiredSelection(
            desiredRange: NSRange,
            currentRange: NSRange,
            isFirstResponder: Bool,
            didReplaceText: Bool
        ) -> Bool {
            guard desiredRange != currentRange else { return false }
            guard isFirstResponder else { return true }
            guard didReplaceText else { return false }
            guard let lastSelectionReportedByUIKit else { return true }
            return desiredRange == lastSelectionReportedByUIKit
        }
    }
}

#endif
