import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorView: View {
    @ObservedObject var viewModel: NativeMarkdownEditorViewModel
    let maxContentWidth: CGFloat

    var body: some View {
        AttributedNoteTextSurface(
            text: $viewModel.attributedContent,
            selection: $viewModel.selection,
            isEditable: true,
            isSelectable: true,
            syncSelection: true,
            autoFocus: true
        )
            .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
            .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: viewModel.attributedContent) { oldValue, _ in
                viewModel.handleContentChange(previous: oldValue)
            }
            .onChange(of: viewModel.selection) { _, _ in
                viewModel.handleSelectionChange()
            }
            .background(DesignTokens.Colors.background)
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension AttributeScopes {
    struct AttributedNoteTextSurfaceAttributes: AttributeScope {
        let markdownEditor: MarkdownEditorAttributes
        #if os(iOS)
        let uiKit: UIKitAttributes
        #elseif os(macOS)
        let appKit: AppKitAttributes
        #endif
    }

    var attributedNoteTextSurface: AttributedNoteTextSurfaceAttributes.Type {
        AttributedNoteTextSurfaceAttributes.self
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteReadOnlyView: View {
    let attributedContent: AttributedString
    let maxContentWidth: CGFloat
    let onTap: (AttributedTextSelection) -> Void

    var body: some View {
        AttributedNoteTextSurface(
            text: .constant(attributedContent),
            selection: .constant(AttributedTextSelection()),
            isEditable: false,
            isSelectable: true,
            syncSelection: false,
            autoFocus: false,
            onTap: onTap
        )
        .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
        .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
        .frame(maxWidth: maxContentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignTokens.Colors.background)
    }
}

#if os(iOS)
@available(iOS 26.0, *)
private struct AttributedNoteTextSurface: UIViewRepresentable {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    let isEditable: Bool
    let isSelectable: Bool
    let syncSelection: Bool
    let autoFocus: Bool
    var onTap: ((AttributedTextSelection) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapRecognizer.cancelsTouchesInView = false
        textView.addGestureRecognizer(tapRecognizer)
        context.coordinator.tapRecognizer = tapRecognizer
        configure(textView, coordinator: context.coordinator)
        textView.attributedText = bridgeToNSAttributedString(text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        configure(textView, coordinator: context.coordinator)

        let updated = bridgeToNSAttributedString(text)
        let nativeSelection = textView.selectedRange
        let nativeContentOffset = textView.contentOffset
        let preserveNativeSelection = syncSelection &&
            isEditable &&
            textView.isFirstResponder &&
            context.coordinator.preferNativeSelectionOnNextUpdate
        let textChanged = !textView.attributedText.isEqual(to: updated)
        if textChanged {
            textView.attributedText = updated
        }

        if syncSelection {
            let desiredRange = nsRange(from: selection, in: text)
            if preserveNativeSelection {
                let clamped = clampedRange(nativeSelection, maxLength: updated.length)
                if textView.selectedRange != clamped {
                    textView.selectedRange = clamped
                }
                context.coordinator.preferNativeSelectionOnNextUpdate = false
            } else {
                let shouldSyncSelection = !isEditable || !textView.isFirstResponder || textChanged
                if shouldSyncSelection && textView.selectedRange != desiredRange {
                    textView.selectedRange = desiredRange
                }
            }
        }
        if syncSelection && isEditable {
            let desiredTypingAttributes = typingAttributesDictionary(
                from: selection.typingAttributes(in: text)
            )
            if !NSDictionary(dictionary: textView.typingAttributes).isEqual(to: desiredTypingAttributes) {
                textView.typingAttributes = desiredTypingAttributes
            }
        }
        if preserveNativeSelection && textChanged {
            textView.layoutIfNeeded()
            let clampedOffset = clampedContentOffset(nativeContentOffset, in: textView)
            if textView.contentOffset != clampedOffset {
                textView.setContentOffset(clampedOffset, animated: false)
            }
        }
        context.coordinator.isUpdating = false
    }

    private func configure(_ textView: UITextView, coordinator: Coordinator) {
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.isScrollEnabled = true
        textView.allowsEditingTextAttributes = false
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        textView.textFormattingConfiguration = UITextFormattingViewController.Configuration(groups: [])
        coordinator.tapRecognizer?.isEnabled = onTap != nil

        guard autoFocus, isEditable else {
            coordinator.didAutoFocus = false
            return
        }

        guard !coordinator.didAutoFocus else { return }
        DispatchQueue.main.async {
            guard textView.window != nil else { return }
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            coordinator.didAutoFocus = true
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AttributedNoteTextSurface
        var isUpdating: Bool = false
        var didAutoFocus: Bool = false
        var preferNativeSelectionOnNextUpdate: Bool = false
        weak var tapRecognizer: UITapGestureRecognizer?

        init(_ parent: AttributedNoteTextSurface) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let onTap = parent.onTap else { return }
            guard let textView = recognizer.view as? UITextView else {
                onTap(AttributedTextSelection())
                return
            }
            let location = recognizer.location(in: textView)
            let tappedRange = tappedInsertionRange(in: textView, location: location)
            let updatedText = bridgeToAttributedString(textView.attributedText)
            let updatedSelection = selectionFromRange(tappedRange, in: updatedText)
            onTap(updatedSelection)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating, parent.isEditable else { return }
            let updatedText = bridgeToAttributedString(textView.attributedText)
            let updatedSelection = selectionFromRange(textView.selectedRange, in: updatedText)
            preferNativeSelectionOnNextUpdate = true
            parent.text = updatedText
            if parent.syncSelection {
                parent.selection = updatedSelection
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating, parent.syncSelection else { return }
            let updatedText = bridgeToAttributedString(textView.attributedText)
            let updatedSelection = selectionFromRange(textView.selectedRange, in: updatedText)
            preferNativeSelectionOnNextUpdate = true
            parent.selection = updatedSelection
        }
    }
}
#elseif os(macOS)
@available(macOS 26.0, *)
private struct AttributedNoteTextSurface: NSViewRepresentable {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    let isEditable: Bool
    let isSelectable: Bool
    let syncSelection: Bool
    let autoFocus: Bool
    var onTap: ((AttributedTextSelection) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator

        let tapRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapRecognizer.numberOfClicksRequired = 1
        tapRecognizer.delaysPrimaryMouseButtonEvents = false
        textView.addGestureRecognizer(tapRecognizer)
        context.coordinator.tapRecognizer = tapRecognizer

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        configure(scrollView, textView: textView, coordinator: context.coordinator)
        textView.textStorage?.setAttributedString(bridgeToNSAttributedString(text))
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.isUpdating = true
        configure(scrollView, textView: textView, coordinator: context.coordinator)

        let updated = bridgeToNSAttributedString(text)
        let nativeSelection = textView.selectedRange()
        let nativeContentOrigin = scrollView.contentView.bounds.origin
        let isFocused = scrollView.window?.firstResponder === textView
        let preserveNativeSelection = syncSelection &&
            isEditable &&
            isFocused &&
            context.coordinator.preferNativeSelectionOnNextUpdate
        let textChanged = !textView.attributedString().isEqual(to: updated)
        if textChanged {
            textView.textStorage?.setAttributedString(updated)
        }

        if syncSelection {
            let desiredRange = nsRange(from: selection, in: text)
            if preserveNativeSelection {
                let clamped = clampedRange(nativeSelection, maxLength: updated.length)
                if textView.selectedRange() != clamped {
                    textView.setSelectedRange(clamped)
                }
                context.coordinator.preferNativeSelectionOnNextUpdate = false
            } else {
                let shouldSyncSelection = !isEditable || !isFocused || textChanged
                if shouldSyncSelection && textView.selectedRange() != desiredRange {
                    textView.setSelectedRange(desiredRange)
                }
            }
        }
        if syncSelection && isEditable {
            let desiredTypingAttributes = typingAttributesDictionary(
                from: selection.typingAttributes(in: text)
            )
            if !NSDictionary(dictionary: textView.typingAttributes).isEqual(to: desiredTypingAttributes) {
                textView.typingAttributes = desiredTypingAttributes
            }
        }
        if preserveNativeSelection && textChanged {
            textView.layoutSubtreeIfNeeded()
            let clampedOrigin = clampedContentOrigin(nativeContentOrigin, in: scrollView)
            if scrollView.contentView.bounds.origin != clampedOrigin {
                scrollView.contentView.setBoundsOrigin(clampedOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        context.coordinator.isUpdating = false
    }

    private func configure(
        _ scrollView: NSScrollView,
        textView: NSTextView,
        coordinator: Coordinator
    ) {
        textView.drawsBackground = false
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.allowsImageEditing = false
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        scrollView.hasVerticalScroller = true
        coordinator.tapRecognizer?.isEnabled = onTap != nil

        guard autoFocus, isEditable else {
            coordinator.didAutoFocus = false
            return
        }

        guard !coordinator.didAutoFocus else { return }
        DispatchQueue.main.async {
            guard let window = scrollView.window else { return }
            if window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
            coordinator.didAutoFocus = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AttributedNoteTextSurface
        var isUpdating: Bool = false
        var didAutoFocus: Bool = false
        var preferNativeSelectionOnNextUpdate: Bool = false
        weak var tapRecognizer: NSClickGestureRecognizer?

        init(_ parent: AttributedNoteTextSurface) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: NSClickGestureRecognizer) {
            guard let onTap = parent.onTap else { return }
            guard let textView = recognizer.view as? NSTextView else {
                onTap(AttributedTextSelection())
                return
            }
            let point = recognizer.location(in: textView)
            let offset = textView.characterIndexForInsertion(at: point)
            let clampedOffset = min(max(0, offset), textView.string.utf16.count)
            let tappedRange = NSRange(location: clampedOffset, length: 0)
            let updatedText = bridgeToAttributedString(textView.attributedString())
            let updatedSelection = selectionFromRange(tappedRange, in: updatedText)
            onTap(updatedSelection)
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            let updatedText = bridgeToAttributedString(textView.attributedString())
            let updatedSelection = selectionFromRange(textView.selectedRange(), in: updatedText)
            preferNativeSelectionOnNextUpdate = true
            parent.text = updatedText
            if parent.syncSelection {
                parent.selection = updatedSelection
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView,
                  parent.syncSelection else { return }
            let updatedText = bridgeToAttributedString(textView.attributedString())
            let updatedSelection = selectionFromRange(textView.selectedRange(), in: updatedText)
            preferNativeSelectionOnNextUpdate = true
            parent.selection = updatedSelection
        }
    }
}
#endif
