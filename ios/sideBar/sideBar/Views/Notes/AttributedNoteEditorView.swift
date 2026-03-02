import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorView: View {
    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let onTap: ((AttributedTextSelection) -> Void)?

    var body: some View {
        AttributedNoteTextSurface(
            text: $viewModel.attributedContent,
            selection: $viewModel.selection,
            isEditable: isEditable,
            isSelectable: true,
            syncSelection: isEditable,
            autoFocus: isEditable,
            onTextDidChange: isEditable ? { previous, sourceGeneration in
                viewModel.handleContentChange(
                    previous: previous,
                    sourceGeneration: sourceGeneration
                )
            } : nil,
            onSelectionDidChange: isEditable ? { sourceGeneration in
                viewModel.handleSelectionChange(sourceGeneration: sourceGeneration)
            } : nil,
            onTap: onTap
        )
            .padding(.horizontal, NoteTextLayout.horizontalPadding)
            .padding(.vertical, NoteTextLayout.verticalPadding)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Colors.background)
    }
}
@available(iOS 26.0, macOS 26.0, *)
extension AttributeScopes {
    struct AttributedNoteTextSurfaceAttributes: AttributeScope {
        let noteTextEditor: NoteTextEditorAttributes
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
#if os(iOS)
@available(iOS 26.0, *)
private struct AttributedNoteTextSurface: UIViewRepresentable {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    let isEditable: Bool
    let isSelectable: Bool
    let syncSelection: Bool
    let autoFocus: Bool
    var onTextDidChange: ((AttributedString, Int) -> Void)?
    var onSelectionDidChange: ((Int) -> Void)?
    var onTap: ((AttributedTextSelection) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        suppressSystemFormattingControls(in: textView)
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

        let synchronizedTextLength: Int
        let nativeSelection = textView.selectedRange
        let nativeContentOffset = textView.contentOffset
        let preserveNativeSelection = syncSelection &&
            isEditable &&
            textView.isFirstResponder &&
            context.coordinator.preferNativeSelectionOnNextUpdate
        var textChanged = false
        let bridged = bridgeToNSAttributedString(text)
        synchronizedTextLength = bridged.length
        if !textView.attributedText.isEqual(to: bridged) {
            textView.attributedText = bridged
            textChanged = true
        }

        if syncSelection {
            let desiredRange = nsRange(from: selection, in: text)
            if preserveNativeSelection {
                let clamped = clampedRange(nativeSelection, maxLength: synchronizedTextLength)
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

    private func suppressSystemFormattingControls(in textView: UITextView) {
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        textView.textFormattingConfiguration = UITextFormattingViewController.Configuration(groups: [])
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AttributedNoteTextSurface
        var isUpdating: Bool = false
        var didAutoFocus: Bool = false
        var preferNativeSelectionOnNextUpdate: Bool = false
        var contentChangeGeneration: Int = 0
        var selectionChangeGeneration: Int = 0
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
            contentChangeGeneration &+= 1
            let generation = contentChangeGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                let previousText = self.parent.text
                self.parent.text = updatedText
                if self.parent.syncSelection {
                    self.parent.selection = updatedSelection
                }
                guard let onTextDidChange = self.parent.onTextDidChange else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isUpdating else { return }
                    onTextDidChange(previousText, generation)
                }
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating, parent.syncSelection else { return }
            let updatedSelection = selectionFromRange(
                textView.selectedRange,
                in: bridgeToAttributedString(textView.attributedText)
            )
            preferNativeSelectionOnNextUpdate = true
            selectionChangeGeneration &+= 1
            let generation = selectionChangeGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                guard self.parent.syncSelection else { return }
                self.parent.selection = updatedSelection
                guard let onSelectionDidChange = self.parent.onSelectionDidChange else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isUpdating else { return }
                    onSelectionDidChange(generation)
                }
            }
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
    var onTextDidChange: ((AttributedString, Int) -> Void)?
    var onSelectionDidChange: ((Int) -> Void)?
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
        let nativeContentOrigin = scrollView.contentView.bounds.origin
        let isFocused = scrollView.window?.firstResponder === textView
        let preserveNativeSelection = syncSelection &&
            isEditable &&
            isFocused &&
            context.coordinator.preferNativeSelectionOnNextUpdate
        let syncResult = synchronizeMacText(
            textView: textView
        )
        synchronizeMacSelection(
            textView: textView,
            coordinator: context.coordinator,
            synchronizedTextLength: syncResult.synchronizedTextLength,
            textChanged: syncResult.textChanged,
            preserveNativeSelection: preserveNativeSelection,
            isFocused: isFocused
        )
        synchronizeMacTypingAttributes(textView: textView)
        if preserveNativeSelection && syncResult.textChanged {
            textView.layoutSubtreeIfNeeded()
            let clampedOrigin = clampedContentOrigin(nativeContentOrigin, in: scrollView)
            if scrollView.contentView.bounds.origin != clampedOrigin {
                scrollView.contentView.setBoundsOrigin(clampedOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        context.coordinator.isUpdating = false
    }

    private func synchronizeMacText(
        textView: NSTextView
    ) -> (synchronizedTextLength: Int, textChanged: Bool) {
        let bridged = bridgeToNSAttributedString(text)
        let synchronizedTextLength = bridged.length
        guard !textView.attributedString().isEqual(to: bridged) else {
            return (synchronizedTextLength, false)
        }
        textView.textStorage?.setAttributedString(bridged)
        return (synchronizedTextLength, true)
    }

    private func synchronizeMacSelection(
        textView: NSTextView,
        coordinator: Coordinator,
        synchronizedTextLength: Int,
        textChanged: Bool,
        preserveNativeSelection: Bool,
        isFocused: Bool
    ) {
        guard syncSelection else { return }
        let desiredRange = nsRange(from: selection, in: text)
        if preserveNativeSelection {
            let clamped = clampedRange(textView.selectedRange(), maxLength: synchronizedTextLength)
            if textView.selectedRange() != clamped {
                textView.setSelectedRange(clamped)
            }
            coordinator.preferNativeSelectionOnNextUpdate = false
            return
        }
        let shouldSyncSelection = !isEditable || !isFocused || textChanged
        if shouldSyncSelection && textView.selectedRange() != desiredRange {
            textView.setSelectedRange(desiredRange)
        }
    }

    private func synchronizeMacTypingAttributes(textView: NSTextView) {
        guard syncSelection && isEditable else { return }
        let desiredTypingAttributes = typingAttributesDictionary(
            from: selection.typingAttributes(in: text)
        )
        if !NSDictionary(dictionary: textView.typingAttributes).isEqual(to: desiredTypingAttributes) {
            textView.typingAttributes = desiredTypingAttributes
        }
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
        var contentChangeGeneration: Int = 0
        var selectionChangeGeneration: Int = 0
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
            contentChangeGeneration &+= 1
            let generation = contentChangeGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                let previousText = self.parent.text
                self.parent.text = updatedText
                if self.parent.syncSelection {
                    self.parent.selection = updatedSelection
                }
                guard let onTextDidChange = self.parent.onTextDidChange else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isUpdating else { return }
                    onTextDidChange(previousText, generation)
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView,
                  parent.syncSelection else { return }
            let updatedSelection = selectionFromRange(
                textView.selectedRange(),
                in: bridgeToAttributedString(textView.attributedString())
            )
            preferNativeSelectionOnNextUpdate = true
            selectionChangeGeneration &+= 1
            let generation = selectionChangeGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                guard self.parent.syncSelection else { return }
                self.parent.selection = updatedSelection
                guard let onSelectionDidChange = self.parent.onSelectionDidChange else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isUpdating else { return }
                    onSelectionDidChange(generation)
                }
            }
        }
    }
}
#endif
