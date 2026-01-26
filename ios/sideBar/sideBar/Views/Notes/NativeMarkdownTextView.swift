import Foundation
import SwiftUI

#if os(iOS)
@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownTextView: UIViewRepresentable {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var isEditable: Bool = true
    var isSelectable: Bool = true
    var syncSelection: Bool = true
    var isScrollEnabled: Bool = true
    var onTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.allowsEditingTextAttributes = true
        textView.isScrollEnabled = isScrollEnabled
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = NSAttributedString(text)
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
        let nsText = NSAttributedString(text)
        if !textView.attributedText.isEqual(to: nsText) {
            textView.attributedText = nsText
        }
        if syncSelection {
            let desiredRange = nsRange(from: selection, in: text)
            if textView.selectedRange != desiredRange {
                textView.selectedRange = desiredRange
            }
        }
        DispatchQueue.main.async {
            context.coordinator.isUpdating = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeMarkdownTextView
        var isUpdating = false
        var tapRecognizer: UITapGestureRecognizer?

        init(_ parent: NativeMarkdownTextView) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap?()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                self.parent.text = AttributedString(textView.attributedText)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                guard self.parent.syncSelection else { return }
                self.parent.selection = selectionFromRange(textView.selectedRange, in: self.parent.text)
            }
        }
    }
}
#elseif os(macOS)
@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownTextView: NSViewRepresentable {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var isEditable: Bool = true
    var isSelectable: Bool = true
    var syncSelection: Bool = true
    var isScrollEnabled: Bool = true
    var onTap: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.allowsImageEditing = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textStorage?.setAttributedString(NSAttributedString(text))
        let tap = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
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
        let nsText = NSAttributedString(text)
        if !(textView.attributedString().isEqual(to: nsText)) {
            textView.textStorage?.setAttributedString(nsText)
        }
        if syncSelection {
            let desiredRange = nsRange(from: selection, in: text)
            if textView.selectedRange() != desiredRange {
                textView.setSelectedRange(desiredRange)
            }
        }
        DispatchQueue.main.async {
            context.coordinator.isUpdating = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMarkdownTextView
        var isUpdating = false
        var tapRecognizer: NSClickGestureRecognizer?

        init(_ parent: NativeMarkdownTextView) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap?()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                self.parent.text = AttributedString(textView.attributedString())
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                guard self.parent.syncSelection else { return }
                self.parent.selection = selectionFromRange(textView.selectedRange(), in: self.parent.text)
            }
        }
    }
}
#endif

@available(iOS 26.0, macOS 26.0, *)
private func nsRange(from selection: AttributedTextSelection, in text: AttributedString) -> NSRange {
    let string = String(text.characters)
    switch selection.indices(in: text) {
    case .insertionPoint(let index):
        let charOffset = text.characters.distance(from: text.startIndex, to: index)
        let stringIndex = string.index(string.startIndex, offsetBy: charOffset)
        let location = stringIndex.utf16Offset(in: string)
        return NSRange(location: location, length: 0)
    case .ranges(let ranges):
        guard let first = ranges.ranges.first else {
            return NSRange(location: 0, length: 0)
        }
        let lowerOffset = text.characters.distance(from: text.startIndex, to: first.lowerBound)
        let upperOffset = text.characters.distance(from: text.startIndex, to: first.upperBound)
        let lowerIndex = string.index(string.startIndex, offsetBy: lowerOffset)
        let upperIndex = string.index(string.startIndex, offsetBy: upperOffset)
        let location = lowerIndex.utf16Offset(in: string)
        let length = upperIndex.utf16Offset(in: string) - location
        return NSRange(location: location, length: max(0, length))
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func selectionFromRange(_ range: NSRange, in text: AttributedString) -> AttributedTextSelection {
    let string = String(text.characters)
    let maxLocation = string.utf16.count
    let safeLocation = min(max(0, range.location), maxLocation)
    let safeEnd = min(max(0, range.location + range.length), maxLocation)
    let startIndex = String.Index(utf16Offset: safeLocation, in: string)
    let endIndex = String.Index(utf16Offset: safeEnd, in: string)
    let startOffset = string.distance(from: string.startIndex, to: startIndex)
    let endOffset = string.distance(from: string.startIndex, to: endIndex)
    let start = text.index(text.startIndex, offsetByCharacters: startOffset)
    let end = text.index(text.startIndex, offsetByCharacters: endOffset)
    if start == end {
        return AttributedTextSelection(range: start..<start)
    }
    return AttributedTextSelection(range: start..<end)
}
