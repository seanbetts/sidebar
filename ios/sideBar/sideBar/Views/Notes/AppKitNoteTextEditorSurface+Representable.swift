#if os(macOS)
import AppKit
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension AppKitNoteTextEditorSurface {
    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView()
        textView.drawsBackground = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.shouldAutofocus = isEditable && shouldAutofocus
        textView.onEscapeCommand = onEscape
        textView.onInitialPresentationReady = onInitialPresentationReady
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
        NotesTransitionDebugTrace.log(
            "appkitEditor.makeNSView",
            details: [
                "editable=\(isEditable)",
                "shouldAutofocus=\(textView.shouldAutofocus)",
                "maxContentWidth=\(NotesTransitionDebugTrace.format(maxContentWidth))"
            ].joined(separator: " ")
        )

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }

        textView.isEditable = isEditable
        textView.shouldAutofocus = isEditable && shouldAutofocus
        textView.onEscapeCommand = onEscape
        textView.onInitialPresentationReady = onInitialPresentationReady
        textView.maxReadableContentWidth = maxContentWidth

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
        let displaySelectedRange = SelectableNoteReadView.editorDisplaySelectedRange(
            in: viewModel.currentPersistenceSnapshot().document,
            logicalSelectedRange: selectedRange
        )
        if textView.selectedRange() != displaySelectedRange {
            context.coordinator.isApplyingProgrammaticSelection = true
            textView.setSelectedRange(displaySelectedRange)
            context.coordinator.isApplyingProgrammaticSelection = false
        }

        textView.scheduleAutofocusIfNeeded()
        textView.scheduleInitialPresentationReadyIfNeeded()

        let typingAttributes = bridgedTypingAttributes(from: viewModel.attributedContent)
        if NSDictionary(dictionary: textView.typingAttributes).isEqual(to: typingAttributes) == false {
            textView.typingAttributes = typingAttributes
        }
        NotesTransitionDebugTrace.log(
            "appkitEditor.updateNSView",
            details: [
                "editable=\(isEditable)",
                "shouldAutofocus=\(textView.shouldAutofocus)",
                "selectedRange=\(NotesTransitionDebugTrace.format(textView.selectedRange()))",
                "renderGeneration=\(viewModel.renderGeneration)",
                "textBounds=\(NotesTransitionDebugTrace.format(textView.bounds))",
                "textInset=\(NotesTransitionDebugTrace.format(textView.textContainerInset))"
            ].joined(separator: " ")
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = scrollView.documentView as? NSTextView,
           textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }
}
#endif
