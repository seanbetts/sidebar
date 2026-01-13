import SwiftUI

struct MarkdownTextEditor: View {
    @Binding var attributedText: NSAttributedString
    @Binding var selection: NSRange
    let isEditable: Bool
    var body: some View {
        #if os(macOS)
        MarkdownTextEditorMac(
            attributedText: $attributedText,
            selection: $selection,
            isEditable: isEditable
        )
        #else
        MarkdownTextEditorIOS(
            attributedText: $attributedText,
            selection: $selection,
            isEditable: isEditable
        )
        #endif
    }
}

#if os(macOS)
import AppKit

private struct MarkdownTextEditorMac: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var selection: NSRange
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownNSTextView()
        textView.isRichText = true
        let baseFont = NSFont.preferredFont(forTextStyle: .body)
        textView.font = baseFont
        textView.typingAttributes = [.font: baseFont]
        textView.textContainerInset = NSSize(width: 20, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = context.coordinator
        textView.drawsBackground = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let needsTextUpdate = !context.coordinator.lastKnownAttributedText.isEqual(to: attributedText)
        if !context.coordinator.isUpdatingText, needsTextUpdate {
            context.coordinator.isApplyingExternalUpdate = true
            context.coordinator.isUpdatingText = true
            textView.textStorage?.setAttributedString(attributedText)
            context.coordinator.isUpdatingText = false
            context.coordinator.isApplyingExternalUpdate = false
            context.coordinator.lastKnownAttributedText = attributedText
        }
        textView.isEditable = isEditable
        if selection != context.coordinator.lastKnownSelection, textView.selectedRange != selection {
            context.coordinator.isApplyingExternalUpdate = true
            context.coordinator.isUpdatingSelection = true
            textView.setSelectedRange(selection)
            context.coordinator.isUpdatingSelection = false
            context.coordinator.isApplyingExternalUpdate = false
            context.coordinator.lastKnownSelection = selection
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MarkdownTextEditorMac
        var isUpdatingText = false
        var isUpdatingSelection = false
        var isApplyingExternalUpdate = false
        var lastKnownAttributedText = NSAttributedString(string: "")
        var lastKnownSelection = NSRange(location: 0, length: 0)

        init(parent: MarkdownTextEditorMac) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdatingText, !isApplyingExternalUpdate else { return }
            let updated = textView.attributedString()
            parent.attributedText = updated
            lastKnownAttributedText = updated
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdatingSelection, !isApplyingExternalUpdate else { return }
            let range = textView.selectedRange()
            parent.selection = range
            lastKnownSelection = range
        }
    }
}

private final class MarkdownNSTextView: NSTextView {
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let font = typingAttributes[.font] as? NSFont ?? self.font ?? NSFont.preferredFont(forTextStyle: .body)
        let height = font.ascender - font.descender
        let adjusted = NSRect(
            x: rect.origin.x,
            y: rect.midY - height / 2,
            width: rect.width,
            height: height
        )
        super.drawInsertionPoint(in: adjusted, color: color, turnedOn: flag)
    }
}
#else
import UIKit

private struct MarkdownTextEditorIOS: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var selection: NSRange
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = MarkdownUITextView()
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        textView.font = baseFont
        textView.typingAttributes = [.font: baseFont]
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let needsTextUpdate = !context.coordinator.lastKnownAttributedText.isEqual(to: attributedText)
        if !context.coordinator.isUpdatingText, needsTextUpdate {
            context.coordinator.isApplyingExternalUpdate = true
            context.coordinator.isUpdatingText = true
            uiView.attributedText = attributedText
            context.coordinator.isUpdatingText = false
            context.coordinator.isApplyingExternalUpdate = false
            context.coordinator.lastKnownAttributedText = attributedText
        }
        uiView.isEditable = isEditable
        if selection != context.coordinator.lastKnownSelection, uiView.selectedRange != selection {
            context.coordinator.isApplyingExternalUpdate = true
            context.coordinator.isUpdatingSelection = true
            uiView.selectedRange = selection
            context.coordinator.isUpdatingSelection = false
            context.coordinator.isApplyingExternalUpdate = false
            context.coordinator.lastKnownSelection = selection
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: MarkdownTextEditorIOS
        var isUpdatingText = false
        var isUpdatingSelection = false
        var isApplyingExternalUpdate = false
        var lastKnownAttributedText = NSAttributedString(string: "")
        var lastKnownSelection = NSRange(location: 0, length: 0)

        init(parent: MarkdownTextEditorIOS) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingText, !isApplyingExternalUpdate else { return }
            let updated = textView.attributedText ?? NSAttributedString(string: "")
            parent.attributedText = updated
            lastKnownAttributedText = updated
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingSelection, !isApplyingExternalUpdate else { return }
            parent.selection = textView.selectedRange
            lastKnownSelection = textView.selectedRange
        }
    }
}

private final class MarkdownUITextView: UITextView {
    override func caretRect(for position: UITextPosition) -> CGRect {
        let rect = super.caretRect(for: position)
        let font = typingAttributes[.font] as? UIFont ?? self.font ?? UIFont.preferredFont(forTextStyle: .body)
        let height = font.lineHeight
        return CGRect(
            x: rect.origin.x,
            y: rect.midY - height / 2,
            width: rect.width,
            height: height
        )
    }
}
#endif
