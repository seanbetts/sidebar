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
private extension AttributeScopes {
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
    let onTap: () -> Void

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
    var onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
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
        if preserveNativeSelection && textChanged {
            textView.layoutIfNeeded()
            let clampedOffset = clampedContentOffset(nativeContentOffset, in: textView)
            if textView.contentOffset != clampedOffset {
                textView.setContentOffset(clampedOffset, animated: false)
            }
        }

        DispatchQueue.main.async {
            context.coordinator.isUpdating = false
        }
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

        @objc func handleTap() {
            parent.onTap?()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            let updatedText = bridgeToAttributedString(textView.attributedText)
            let updatedSelection = selectionFromRange(textView.selectedRange, in: updatedText)
            preferNativeSelectionOnNextUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                self.parent.text = updatedText
                if self.parent.syncSelection {
                    self.parent.selection = updatedSelection
                }
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating, parent.syncSelection else { return }
            let updatedText = bridgeToAttributedString(textView.attributedText)
            let updatedSelection = selectionFromRange(textView.selectedRange, in: updatedText)
            preferNativeSelectionOnNextUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                guard self.parent.syncSelection else { return }
                self.parent.selection = updatedSelection
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
    var onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator

        let tapRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
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
        if preserveNativeSelection && textChanged {
            textView.layoutSubtreeIfNeeded()
            let clampedOrigin = clampedContentOrigin(nativeContentOrigin, in: scrollView)
            if scrollView.contentView.bounds.origin != clampedOrigin {
                scrollView.contentView.setBoundsOrigin(clampedOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        DispatchQueue.main.async {
            context.coordinator.isUpdating = false
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
        weak var tapRecognizer: NSClickGestureRecognizer?

        init(_ parent: AttributedNoteTextSurface) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap?()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            let updatedText = bridgeToAttributedString(textView.attributedString())
            let updatedSelection = selectionFromRange(textView.selectedRange(), in: updatedText)
            preferNativeSelectionOnNextUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                self.parent.text = updatedText
                if self.parent.syncSelection {
                    self.parent.selection = updatedSelection
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView,
                  parent.syncSelection else { return }
            let updatedText = bridgeToAttributedString(textView.attributedString())
            let updatedSelection = selectionFromRange(textView.selectedRange(), in: updatedText)
            preferNativeSelectionOnNextUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                guard self.parent.syncSelection else { return }
                self.parent.selection = updatedSelection
            }
        }
    }
}
#endif

@available(iOS 26.0, macOS 26.0, *)
private func bridgeToNSAttributedString(_ text: AttributedString) -> NSAttributedString {
    if let scoped = try? NSAttributedString(text, including: \.attributedNoteTextSurface) {
        return scoped
    }
    return NSAttributedString(text)
}

@available(iOS 26.0, macOS 26.0, *)
private func bridgeToAttributedString(_ text: NSAttributedString) -> AttributedString {
    if let scoped = try? AttributedString(text, including: \.attributedNoteTextSurface) {
        return scoped
    }
    return AttributedString(text)
}

@available(iOS 26.0, macOS 26.0, *)
private func nsRange(from selection: AttributedTextSelection, in text: AttributedString) -> NSRange {
    let string = String(text.characters)
    switch selection.indices(in: text) {
    case .insertionPoint(let index):
        let characterOffset = text.characters.distance(from: text.startIndex, to: index)
        let stringIndex = string.index(string.startIndex, offsetBy: characterOffset)
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

@available(iOS 26.0, macOS 26.0, *)
private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(max(range.location, 0), maxLength)
    let safeLength = min(max(range.length, 0), max(0, maxLength - safeLocation))
    return NSRange(location: safeLocation, length: safeLength)
}

#if os(iOS)
@available(iOS 26.0, *)
private func clampedContentOffset(_ offset: CGPoint, in textView: UITextView) -> CGPoint {
    let inset = textView.adjustedContentInset
    let minX = -inset.left
    let minY = -inset.top
    let maxX = max(minX, textView.contentSize.width - textView.bounds.width + inset.right)
    let maxY = max(minY, textView.contentSize.height - textView.bounds.height + inset.bottom)
    return CGPoint(
        x: min(max(offset.x, minX), maxX),
        y: min(max(offset.y, minY), maxY)
    )
}
#elseif os(macOS)
@available(macOS 26.0, *)
private func clampedContentOrigin(_ origin: CGPoint, in scrollView: NSScrollView) -> CGPoint {
    guard let documentView = scrollView.documentView else {
        return origin
    }
    let contentBounds = scrollView.contentView.bounds
    let maxX = max(0, documentView.bounds.width - contentBounds.width)
    let maxY = max(0, documentView.bounds.height - contentBounds.height)
    return CGPoint(
        x: min(max(origin.x, 0), maxX),
        y: min(max(origin.y, 0), maxY)
    )
}
#endif
