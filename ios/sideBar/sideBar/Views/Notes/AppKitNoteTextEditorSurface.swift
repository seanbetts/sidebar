#if os(macOS)
import AppKit
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
private struct AppKitNoteTextEditorScrollLayoutContext {
    let layoutManager: NSLayoutManager
    let textContainer: NSTextContainer
    let contentHeight: CGFloat
}

@available(iOS 26.0, macOS 26.0, *)
private final class AppKitNoteEditorScrollView: NSScrollView {
    var onViewportOffsetChange: ((CGPoint) -> Void)?
    private var lastReportedViewportOffset: CGPoint?

    override func layout() {
        super.layout()
        reportViewportOffsetIfNeeded(force: true)
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        reportViewportOffsetIfNeeded()
    }

    private func reportViewportOffsetIfNeeded(force: Bool = false) {
        let viewportOffset = contentView.bounds.origin
        guard force || lastReportedViewportOffset != viewportOffset else { return }
        lastReportedViewportOffset = viewportOffset
        onViewportOffsetChange?(viewportOffset)
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct AppKitNoteTextEditorSurface: NSViewRepresentable {
    fileprivate struct RenderSignature: Equatable {
        let renderGeneration: UInt64
        let baseFontSize: CGFloat
    }

    final class EditorTextView: NSTextView {
        private static let baseTextContainerInset = NSSize(
            width: NoteTextLayout.horizontalPadding,
            height: NoteTextLayout.verticalPadding
        )

        var shouldAutofocus = false
        var pendingSelectionViewportAnchorY: CGFloat?
        var onPendingSelectionViewportAnchorApplied: (() -> Void)?
        var onDidMoveToWindow: (() -> Void)?
        private var isApplyingPendingViewportAnchor = false
        var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
            didSet { needsLayout = true }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onDidMoveToWindow?()
        }

        override func layout() {
            super.layout()
            updateTextContainerInset()
            applyPendingViewportAnchorIfNeeded()
        }

        func positionCurrentSelection(atViewportAnchorY viewportAnchorY: CGFloat) {
            guard let scrollView = enclosingScrollView,
                  let clipView = scrollView.contentView as NSClipView?,
                  let layout = ensureDocumentLayoutForScrolling(),
                  let selectionMidY = selectionMidY(layoutManager: layout.layoutManager, textContainer: layout.textContainer) else {
                return
            }
            let visibleRect = clipView.bounds
            guard visibleRect.height > 0 else { return }
            let clampedViewportAnchorY = min(max(viewportAnchorY, 0), visibleRect.height)
            let targetMidY = visibleRect.minY + clampedViewportAnchorY
            var targetOrigin = visibleRect.origin
            targetOrigin.y += selectionMidY - targetMidY
            let maxY = max(layout.contentHeight - visibleRect.height, 0)
            targetOrigin.y = min(max(targetOrigin.y, 0), maxY)
            clipView.scroll(to: targetOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }

        private func updateTextContainerInset() {
            let extraHorizontalInset = max((bounds.width - maxReadableContentWidth) / 2, 0)
            let resolvedInset = NSSize(
                width: Self.baseTextContainerInset.width + extraHorizontalInset,
                height: Self.baseTextContainerInset.height
            )
            guard textContainerInset != resolvedInset else { return }
            textContainerInset = resolvedInset
        }

        private func ensureDocumentLayoutForScrolling() -> AppKitNoteTextEditorScrollLayoutContext? {
            guard let layoutManager,
                  let textContainer else {
                return nil
            }
            let availableWidth = max(bounds.width - (textContainerInset.width * 2), 0)
            textContainer.containerSize = NSSize(
                width: availableWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = max(
                ceil(layoutManager.usedRect(for: textContainer).height + (textContainerInset.height * 2)),
                enclosingScrollView?.contentView.bounds.height ?? 0
            )
            if abs(frame.height - contentHeight) > 0.5 {
                setFrameSize(NSSize(width: frame.width, height: contentHeight))
            }
            return AppKitNoteTextEditorScrollLayoutContext(
                layoutManager: layoutManager,
                textContainer: textContainer,
                contentHeight: contentHeight
            )
        }

        private func selectionMidY(
            layoutManager: NSLayoutManager,
            textContainer: NSTextContainer
        ) -> CGFloat? {
            guard layoutManager.numberOfGlyphs > 0 else {
                return textContainerInset.height
            }
            let selectionLocation = min(max(selectedRange().location, 0), string.utf16.count)
            let glyphIndex: Int
            if selectionLocation >= string.utf16.count {
                glyphIndex = max(layoutManager.numberOfGlyphs - 1, 0)
            } else {
                glyphIndex = layoutManager.glyphIndexForCharacter(at: selectionLocation)
            }
            let lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            )
            return textContainerInset.height + lineRect.midY
        }

        private func applyPendingViewportAnchorIfNeeded() {
            guard let pendingSelectionViewportAnchorY,
                  window != nil,
                  isApplyingPendingViewportAnchor == false else {
                return
            }
            isApplyingPendingViewportAnchor = true
            defer { isApplyingPendingViewportAnchor = false }
            if shouldAutofocus, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            positionCurrentSelection(atViewportAnchorY: pendingSelectionViewportAnchorY)
            self.pendingSelectionViewportAnchorY = nil
            onPendingSelectionViewportAnchorApplied?()
        }
    }

    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let shouldAutofocus: Bool
    let onViewportOffsetChange: ((CGPoint) -> Void)?
    let pendingSelectionViewportAnchorY: CGFloat?
    let onPendingSelectionViewportAnchorApplied: (() -> Void)?

    init(
        viewModel: NativeNoteEditorViewModel,
        maxContentWidth: CGFloat,
        isEditable: Bool,
        shouldAutofocus: Bool = true,
        onViewportOffsetChange: ((CGPoint) -> Void)? = nil,
        pendingSelectionViewportAnchorY: CGFloat? = nil,
        onPendingSelectionViewportAnchorApplied: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.isEditable = isEditable
        self.shouldAutofocus = shouldAutofocus
        self.onViewportOffsetChange = onViewportOffsetChange
        self.pendingSelectionViewportAnchorY = pendingSelectionViewportAnchorY
        self.onPendingSelectionViewportAnchorApplied = onPendingSelectionViewportAnchorApplied
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView()
        textView.drawsBackground = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.shouldAutofocus = isEditable && shouldAutofocus
        textView.pendingSelectionViewportAnchorY = pendingSelectionViewportAnchorY
        textView.onPendingSelectionViewportAnchorApplied = onPendingSelectionViewportAnchorApplied
        textView.maxReadableContentWidth = maxContentWidth
        textView.textColor = .labelColor
        textView.insertionPointColor = NoteTextAppearance.caretTintColor
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("Notes editor")
        textView.onDidMoveToWindow = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator else { return }
            Self.scheduleAutofocusIfNeeded(for: textView, coordinator: coordinator)
        }

        let scrollView = AppKitNoteEditorScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.onViewportOffsetChange = onViewportOffsetChange
        scrollView.documentView = textView

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }

        textView.isEditable = isEditable
        textView.shouldAutofocus = isEditable && shouldAutofocus
        textView.pendingSelectionViewportAnchorY = pendingSelectionViewportAnchorY
        textView.onPendingSelectionViewportAnchorApplied = onPendingSelectionViewportAnchorApplied
        textView.maxReadableContentWidth = maxContentWidth
        if let trackingScrollView = scrollView as? AppKitNoteEditorScrollView {
            trackingScrollView.onViewportOffsetChange = onViewportOffsetChange
        }

        let renderSignature = RenderSignature(
            renderGeneration: viewModel.renderGeneration,
            baseFontSize: viewModel.baseFontSize
        )
        if context.coordinator.lastAppliedRenderSignature != renderSignature {
            let attributedText = bridgedAttributedText(from: viewModel.attributedContent)
            context.coordinator.isApplyingProgrammaticText = true
            textView.textStorage?.setAttributedString(attributedText)
            context.coordinator.isApplyingProgrammaticText = false
            context.coordinator.lastAppliedRenderSignature = renderSignature
        }

        let selectedRange = viewModel.utf16SelectedRange(in: viewModel.attributedContent)
        if textView.selectedRange() != selectedRange {
            context.coordinator.isApplyingProgrammaticSelection = true
            textView.setSelectedRange(selectedRange)
            context.coordinator.isApplyingProgrammaticSelection = false
        }

        Self.scheduleAutofocusIfNeeded(for: textView, coordinator: context.coordinator)

        let typingAttributes = bridgedTypingAttributes(from: viewModel.attributedContent)
        if NSDictionary(dictionary: textView.typingAttributes).isEqual(to: typingAttributes) == false {
            textView.typingAttributes = typingAttributes
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = scrollView.documentView as? NSTextView,
           textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
        if let trackingScrollView = scrollView as? AppKitNoteEditorScrollView {
            trackingScrollView.onViewportOffsetChange = nil
        }
    }

    private static func scheduleAutofocusIfNeeded(
        for textView: EditorTextView,
        coordinator: Coordinator
    ) {
        guard textView.shouldAutofocus,
              textView.window != nil,
              coordinator.hasScheduledAutofocus == false,
              textView.window?.firstResponder !== textView || textView.pendingSelectionViewportAnchorY != nil else {
            return
        }
        coordinator.hasScheduledAutofocus = true
        DispatchQueue.main.async { [weak textView, weak coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.hasScheduledAutofocus = false
            guard textView.shouldAutofocus, textView.window != nil else { return }
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }
            textView.layoutSubtreeIfNeeded()
        }
    }

    private func bridgedAttributedText(from text: AttributedString) -> NSAttributedString {
        SelectableNoteReadView.bridgedPlatformAttributedString(
            from: text,
            baseFontSize: viewModel.baseFontSize
        )
    }

    private func bridgedTypingAttributes(from text: AttributedString) -> [NSAttributedString.Key: Any] {
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(viewModel.typingAttributesForInsertion(in: text))
        let bridged = SelectableNoteReadView.bridgedPlatformAttributedString(
            from: sample,
            baseFontSize: viewModel.baseFontSize
        )
        return bridged.attributes(at: 0, effectiveRange: nil)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let viewModel: NativeNoteEditorViewModel
        weak var textView: NSTextView?
        var isApplyingProgrammaticText = false
        var isApplyingProgrammaticSelection = false
        fileprivate var lastAppliedRenderSignature: RenderSignature?
        var hasScheduledAutofocus = false

        init(viewModel: NativeNoteEditorViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticText,
                  let textView = notification.object as? NSTextView else {
                return
            }

            isApplyingProgrammaticText = true
            viewModel.replaceAttributedContent(
                textView.attributedString(),
                selectedUTF16Range: textView.selectedRange()
            )
            isApplyingProgrammaticText = false
            lastAppliedRenderSignature = RenderSignature(
                renderGeneration: viewModel.renderGeneration,
                baseFontSize: viewModel.baseFontSize
            )
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingProgrammaticText,
                  !isApplyingProgrammaticSelection,
                  let textView = notification.object as? NSTextView else {
                return
            }

            let selection = viewModel.selection(
                fromUTF16Range: textView.selectedRange(),
                in: viewModel.attributedContent
            )
            guard selection != viewModel.selection else { return }
            viewModel.selection = selection
            viewModel.handleSelectionChange()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            guard handleStructuralReplacement(
                in: textView,
                selectedRange: textView.selectedRange(),
                replacementText: "\n"
            ) else {
                return false
            }

            return true
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString else { return true }

            if handleStructuralReplacement(
                in: textView,
                selectedRange: affectedCharRange,
                replacementText: replacementString
            ) {
                return false
            }

            return true
        }

        private func handleStructuralReplacement(
            in textView: NSTextView,
            selectedRange: NSRange,
            replacementText: String
        ) -> Bool {
            let selection = viewModel.selection(
                fromUTF16Range: selectedRange,
                in: viewModel.attributedContent
            )
            if selection != viewModel.selection {
                viewModel.selection = selection
                viewModel.handleSelectionChange()
            }

            guard replacementText.contains("\n") else { return false }
            guard viewModel.handleTextReplacement(replacementText) else { return false }

            applyCurrentEditorState(to: textView)
            return true
        }

        private func applyCurrentEditorState(to textView: NSTextView) {
            let bridgedText = SelectableNoteReadView.bridgedPlatformAttributedString(
                from: viewModel.attributedContent,
                baseFontSize: viewModel.baseFontSize
            )
            isApplyingProgrammaticText = true
            textView.textStorage?.setAttributedString(bridgedText)
            isApplyingProgrammaticText = false
            lastAppliedRenderSignature = RenderSignature(
                renderGeneration: viewModel.renderGeneration,
                baseFontSize: viewModel.baseFontSize
            )

            isApplyingProgrammaticSelection = true
            textView.setSelectedRange(viewModel.utf16SelectedRange(in: viewModel.attributedContent))
            isApplyingProgrammaticSelection = false

            var sample = AttributedString("x")
            let range = sample.startIndex..<sample.endIndex
            sample[range].mergeAttributes(viewModel.typingAttributesForInsertion(in: viewModel.attributedContent))
            let bridgedTypingSample = SelectableNoteReadView.bridgedPlatformAttributedString(
                from: sample,
                baseFontSize: viewModel.baseFontSize
            )
            textView.typingAttributes = bridgedTypingSample.attributes(at: 0, effectiveRange: nil)
        }
    }
}
#endif
