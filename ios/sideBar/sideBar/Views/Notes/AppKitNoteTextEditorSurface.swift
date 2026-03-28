#if os(macOS)
import AppKit
import SwiftUI

private struct AppKitNoteTextEditorUndoSnapshot {
    let attributedText: NSAttributedString
    let selectedRange: NSRange
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
        private var didScheduleAutofocus = false
        var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
            didSet { needsLayout = true }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateTextContainerInset()
            scheduleAutofocusIfNeeded()
        }

        override func layout() {
            super.layout()
            updateTextContainerInset()
        }

        func scheduleAutofocusIfNeeded() {
            guard shouldAutofocus, !didScheduleAutofocus, let window else { return }
            didScheduleAutofocus = true
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self,
                      self.shouldAutofocus,
                      let window,
                      self.window === window,
                      window.firstResponder !== self else {
                    return
                }
                window.makeFirstResponder(self)
            }
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
    }

    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let shouldAutofocus: Bool

    init(
        viewModel: NativeNoteEditorViewModel,
        maxContentWidth: CGFloat,
        isEditable: Bool,
        shouldAutofocus: Bool = true
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.isEditable = isEditable
        self.shouldAutofocus = shouldAutofocus
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
        if textView.selectedRange() != selectedRange {
            context.coordinator.isApplyingProgrammaticSelection = true
            textView.setSelectedRange(selectedRange)
            context.coordinator.isApplyingProgrammaticSelection = false
        }

        textView.scheduleAutofocusIfNeeded()

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

        init(viewModel: NativeNoteEditorViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticText,
                  let textView = notification.object as? NSTextView else {
                return
            }

            let attributedText = NSAttributedString(attributedString: textView.attributedString())
            let selectedRange = textView.selectedRange()
            DispatchQueue.main.async {
                self.viewModel.replaceAttributedContent(
                    attributedText,
                    selectedUTF16Range: selectedRange
                )
                self.lastAppliedRenderSignature = RenderSignature(
                    renderGeneration: self.viewModel.renderGeneration,
                    baseFontSize: self.viewModel.baseFontSize
                )
            }
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

            guard viewModel.shouldHandleStructuralTextReplacement(replacementText) else { return false }
            let undoSnapshot = literalUndoSnapshot(
                in: textView,
                selectedRange: selectedRange,
                replacementText: replacementText
            )
            guard viewModel.handleTextReplacement(replacementText) else { return false }

            if let undoSnapshot {
                registerUndoSnapshot(undoSnapshot, on: textView)
            }
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

        private func literalUndoSnapshot(
            in textView: NSTextView,
            selectedRange: NSRange,
            replacementText: String
        ) -> AppKitNoteTextEditorUndoSnapshot? {
            guard replacementText == " " else { return nil }

            let updatedText = NSMutableAttributedString(
                attributedString: textView.attributedString()
            )
            let insertedText = NSAttributedString(
                string: replacementText,
                attributes: textView.typingAttributes
            )
            updatedText.replaceCharacters(in: selectedRange, with: insertedText)
            return AppKitNoteTextEditorUndoSnapshot(
                attributedText: updatedText,
                selectedRange: NSRange(
                    location: selectedRange.location + insertedText.length,
                    length: 0
                )
            )
        }

        private func registerUndoSnapshot(
            _ snapshot: AppKitNoteTextEditorUndoSnapshot,
            on textView: NSTextView
        ) {
            textView.undoManager?.registerUndo(withTarget: self) { target in
                target.restoreUndoSnapshot(snapshot, on: textView)
            }
        }

        private func restoreUndoSnapshot(
            _ snapshot: AppKitNoteTextEditorUndoSnapshot,
            on textView: NSTextView
        ) {
            let redoSnapshot = AppKitNoteTextEditorUndoSnapshot(
                attributedText: textView.attributedString(),
                selectedRange: textView.selectedRange()
            )
            viewModel.replaceAttributedContent(
                snapshot.attributedText,
                selectedUTF16Range: snapshot.selectedRange
            )
            registerUndoSnapshot(redoSnapshot, on: textView)
            applyCurrentEditorState(to: textView)
        }
    }
}
#endif
