#if os(iOS)
import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct UIKitNoteTextEditorSurface: UIViewRepresentable {
    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let shouldAutofocus: Bool
    let formattingBarConfiguration: NoteFormattingBarConfiguration?
    let formattingBarPresentation: NoteFormattingBarPresentation
    let pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?; let pendingSelectionViewportAnchorY: CGFloat?
    let onPendingSelectionTargetApplied: ((AccessoryTextView) -> Void)?; let onDidBeginEditing: ((AccessoryTextView) -> Void)?
    let onViewportSnapshotChange: ((CGPoint, NSRange, CGFloat?) -> Void)?
    let onTextViewReady: ((AccessoryTextView) -> Void)?
    let makeTextView: (() -> AccessoryTextView)?
    let onEscape: (() -> Void)?

    init(
        viewModel: NativeNoteEditorViewModel,
        maxContentWidth: CGFloat,
        isEditable: Bool,
        shouldAutofocus: Bool = true,
        formattingBarConfiguration: NoteFormattingBarConfiguration? = nil,
        formattingBarPresentation: NoteFormattingBarPresentation,
        pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget? = nil,
        pendingSelectionViewportAnchorY: CGFloat? = nil,
        onPendingSelectionTargetApplied: ((AccessoryTextView) -> Void)? = nil,
        onDidBeginEditing: ((AccessoryTextView) -> Void)? = nil,
        onViewportSnapshotChange: ((CGPoint, NSRange, CGFloat?) -> Void)? = nil,
        onTextViewReady: ((AccessoryTextView) -> Void)? = nil,
        makeTextView: (() -> AccessoryTextView)? = nil,
        onEscape: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.isEditable = isEditable
        self.shouldAutofocus = shouldAutofocus
        self.formattingBarConfiguration = formattingBarConfiguration
        self.formattingBarPresentation = formattingBarPresentation
        self.pendingSelectionTarget = pendingSelectionTarget
        self.pendingSelectionViewportAnchorY = pendingSelectionViewportAnchorY
        self.onPendingSelectionTargetApplied = onPendingSelectionTargetApplied
        self.onDidBeginEditing = onDidBeginEditing
        self.onViewportSnapshotChange = onViewportSnapshotChange
        self.onTextViewReady = onTextViewReady
        self.makeTextView = makeTextView
        self.onEscape = onEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> UIKitNoteTextEditorContainerView {
        let textView = makeTextView?() ?? AccessoryTextView()
        textView.isEditable = isEditable
        textView.allowsEditingTextAttributes = false
        textView.shouldAutofocus = isEditable && shouldAutofocus
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.tintColor = NoteTextAppearance.caretTintColor
        textView.accessibilityIdentifier = "notes-editor-text-view"
        textView.textContainer.lineFragmentPadding = 0
        textView.maxReadableContentWidth = maxContentWidth
        textView.onViewportSnapshotChange = onViewportSnapshotChange
        textView.onEscapeCommand = onEscape
        textView.onDidMoveToWindow = { attachedTextView in
            handleTextViewDidMoveToWindow(attachedTextView)
        }
        textView.delegate = context.coordinator
        textView.textFormattingConfiguration = nil
        if shouldShowFormattingAccessory, let formattingBarConfiguration {
            textView.formattingAccessoryView = makeFormattingAccessoryView(
                configuration: formattingBarConfiguration
            )
        }
        let decorationView = UIKitNoteTextEditorContainerView.DecorationView()
        decorationView.textView = textView
        textView.insertSubview(decorationView, at: 0)
        textView.decorationView = decorationView
        let containerView = UIKitNoteTextEditorContainerView(textView: textView)
        onTextViewReady?(textView)
        return containerView
    }

    func updateUIView(_ containerView: UIKitNoteTextEditorContainerView, context: Context) {
        let textView = containerView.textView
        onTextViewReady?(textView)
        context.coordinator.onDidBeginEditing = onDidBeginEditing
        textView.isEditable = isEditable
        textView.shouldAutofocus = isEditable && shouldAutofocus
        textView.maxReadableContentWidth = maxContentWidth
        textView.onViewportSnapshotChange = onViewportSnapshotChange
        textView.onEscapeCommand = onEscape
        textView.onDidMoveToWindow = { attachedTextView in
            handleTextViewDidMoveToWindow(attachedTextView)
        }
        let shouldSuppressAutofocusRevealForPendingSelection =
            pendingSelectionTarget != nil && textView.shouldAutofocus && !textView.isFirstResponder
        if shouldSuppressAutofocusRevealForPendingSelection {
            textView.suppressAutofocusReveal = true
        }
        let needsAccessoryReload = configureFormattingUI(
            for: textView,
            configuration: formattingBarConfiguration
        )
        if needsAccessoryReload, textView.isFirstResponder {
            textView.reloadInputViews()
        }
        let renderSignature = UIKitNoteTextEditorRenderSignature(
            renderGeneration: viewModel.renderGeneration,
            baseFontSize: viewModel.baseFontSize
        )
        let selectedRange = resolvedSelectedRange(
            pendingSelectionTarget: pendingSelectionTarget,
            textView: textView,
            coordinator: context.coordinator
        )
        let isProgrammaticRenderUpdate = context.coordinator.lastAppliedRenderSignature != renderSignature
        applyRenderedTextIfNeeded(
            to: textView,
            coordinator: context.coordinator,
            renderSignature: renderSignature,
            isProgrammaticRenderUpdate: isProgrammaticRenderUpdate
        )
        applySelectionIfNeeded(
            to: textView,
            coordinator: context.coordinator,
            selectedRange: selectedRange
        )
        scheduleAutofocusIfNeeded(for: textView)
        acknowledgePendingSelectionTargetIfNeeded(
            pendingSelectionTarget,
            selectedRange: selectedRange,
            textView: textView,
            coordinator: context.coordinator
        )

        let typingAttributes = bridgedTypingAttributes(from: viewModel.attributedContent)
        if NSDictionary(dictionary: textView.typingAttributes).isEqual(to: typingAttributes) == false {
            textView.typingAttributes = typingAttributes
        }
    }

    static func dismantleUIView(_ containerView: UIKitNoteTextEditorContainerView, coordinator: Void) {
        let textView = containerView.textView
        if textView.isFirstResponder {
            _ = textView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let viewModel: NativeNoteEditorViewModel
        var isApplyingProgrammaticText = false, isApplyingProgrammaticSelection = false
        var lastAppliedRenderSignature: UIKitNoteTextEditorRenderSignature?
        var acknowledgedPendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        var onDidBeginEditing: ((AccessoryTextView) -> Void)?

        init(viewModel: NativeNoteEditorViewModel) {
            self.viewModel = viewModel
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticText else { return }
            (textView as? AccessoryTextView)?.invalidateCodeBlockBackgroundLayout()
            let document = viewModel.currentPersistenceSnapshot().document

            let attributedText = SelectableNoteReadView.expandingChecklistEditorMarkers(
                in: textView.attributedText,
                document: document
            )
            let selectedRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: textView.selectedRange,
                in: textView.attributedText,
                document: document
            )
            DispatchQueue.main.async {
                self.viewModel.replaceAttributedContentFromLiveTextView(
                    attributedText,
                    selectedUTF16Range: selectedRange
                )
                self.lastAppliedRenderSignature = UIKitNoteTextEditorRenderSignature(
                    renderGeneration: self.viewModel.renderGeneration,
                    baseFontSize: self.viewModel.baseFontSize
                )
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticText, !isApplyingProgrammaticSelection else { return }
            guard textView.isFirstResponder else { return }
            let document = viewModel.currentPersistenceSnapshot().document

            let logicalSelectedRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: textView.selectedRange,
                in: textView.attributedText,
                document: document
            )
            let selection = viewModel.selection(
                fromUTF16Range: logicalSelectedRange,
                in: viewModel.attributedContent
            )
            if selection != viewModel.selection {
                viewModel.selection = selection
                viewModel.handleSelectionChange()
            }
            (textView as? AccessoryTextView)?.reportViewportSnapshotIfNeeded(force: true)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard let textView = textView as? AccessoryTextView else { return }
            let document = viewModel.currentPersistenceSnapshot().document
            let logicalSelectedRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: textView.selectedRange,
                in: textView.attributedText,
                document: document
            )
            let selection = viewModel.selection(
                fromUTF16Range: logicalSelectedRange,
                in: viewModel.attributedContent
            )
            if selection != viewModel.selection {
                viewModel.selection = selection
                viewModel.handleSelectionChange()
            }
            textView.reportViewportSnapshotIfNeeded(force: true)
            onDidBeginEditing?(textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard viewModel.shouldHandleStructuralTextReplacement(text) else { return true }
            let document = viewModel.currentPersistenceSnapshot().document

            let logicalRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: range,
                in: textView.attributedText,
                document: document
            )
            let selection = viewModel.selection(
                fromUTF16Range: logicalRange,
                in: viewModel.attributedContent
            )
            if selection != viewModel.selection {
                viewModel.selection = selection
                viewModel.handleSelectionChange()
            }
            let undoSnapshot = literalUndoSnapshot(
                in: textView,
                selectedRange: range,
                replacementText: text
            )
            guard viewModel.handleTextReplacement(text) else { return true }

            if let undoSnapshot {
                registerUndoSnapshot(undoSnapshot, on: textView)
            }
            applyCurrentEditorState(to: textView)
            return false
        }

        private func applyCurrentEditorState(to textView: UITextView) {
            let bridgedText = SelectableNoteReadView.bridgedPlatformEditorAttributedString(
                from: viewModel.attributedContent,
                document: viewModel.currentPersistenceSnapshot().document,
                baseFontSize: viewModel.baseFontSize
            )
            isApplyingProgrammaticText = true
            textView.textStorage.setAttributedString(bridgedText)
            isApplyingProgrammaticText = false
            (textView as? AccessoryTextView)?.invalidateCodeBlockBackgroundLayout()
            lastAppliedRenderSignature = UIKitNoteTextEditorRenderSignature(
                renderGeneration: viewModel.renderGeneration,
                baseFontSize: viewModel.baseFontSize
            )

            isApplyingProgrammaticSelection = true
            textView.selectedRange = SelectableNoteReadView.editorDisplaySelectedRange(
                in: viewModel.currentPersistenceSnapshot().document,
                logicalSelectedRange: viewModel.utf16SelectedRange(in: viewModel.attributedContent)
            )
            isApplyingProgrammaticSelection = false

            var sample = AttributedString("x")
            let sampleRange = sample.startIndex..<sample.endIndex
            sample[sampleRange].mergeAttributes(viewModel.typingAttributesForInsertion(in: viewModel.attributedContent))
            let bridgedTypingSample = SelectableNoteReadView.bridgedPlatformAttributedString(
                from: sample,
                baseFontSize: viewModel.baseFontSize
            )
            textView.typingAttributes = bridgedTypingSample.attributes(at: 0, effectiveRange: nil)
        }

        private func literalUndoSnapshot(
            in textView: UITextView,
            selectedRange: NSRange,
            replacementText: String
        ) -> UIKitNoteTextEditorUndoSnapshot? {
            guard replacementText == " " else { return nil }

            let updatedText = NSMutableAttributedString(attributedString: textView.attributedText)
            let insertedText = NSAttributedString(
                string: replacementText,
                attributes: textView.typingAttributes
            )
            updatedText.replaceCharacters(in: selectedRange, with: insertedText)
            let updatedSelection = NSRange(
                location: selectedRange.location + insertedText.length,
                length: 0
            )
            return UIKitNoteTextEditorUndoSnapshot(
                attributedText: SelectableNoteReadView.expandingChecklistEditorMarkers(
                    in: updatedText,
                    document: viewModel.currentPersistenceSnapshot().document
                ),
                selectedRange: SelectableNoteReadView.logicalEditorSelectedRange(
                    fromDisplaySelectedRange: updatedSelection,
                    in: updatedText,
                    document: viewModel.currentPersistenceSnapshot().document
                )
            )
        }

        private func registerUndoSnapshot(
            _ snapshot: UIKitNoteTextEditorUndoSnapshot,
            on textView: UITextView
        ) {
            textView.undoManager?.registerUndo(withTarget: self) { target in
                target.restoreUndoSnapshot(snapshot, on: textView)
            }
        }

        private func restoreUndoSnapshot(
            _ snapshot: UIKitNoteTextEditorUndoSnapshot,
            on textView: UITextView
        ) {
            let redoSnapshot = UIKitNoteTextEditorUndoSnapshot(
                attributedText: SelectableNoteReadView.expandingChecklistEditorMarkers(
                    in: textView.attributedText,
                    document: viewModel.currentPersistenceSnapshot().document
                ),
                selectedRange: SelectableNoteReadView.logicalEditorSelectedRange(
                    fromDisplaySelectedRange: textView.selectedRange,
                    in: textView.attributedText,
                    document: viewModel.currentPersistenceSnapshot().document
                )
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
