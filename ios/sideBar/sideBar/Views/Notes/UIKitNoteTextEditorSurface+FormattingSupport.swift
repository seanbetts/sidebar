#if os(iOS)
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface {
    func handleTextViewDidMoveToWindow(_ textView: AccessoryTextView) {
        guard textView.window != nil else { return }
        NotesEditEntryDebugTrace.log(
            "textView.didMoveToWindow",
            details: NotesEditEntryDebugTrace.textViewSummary(textView)
        )
        onTextViewReady?(textView)
        scheduleAutofocusIfNeeded(for: textView)
    }

    func scheduleAutofocusIfNeeded(for textView: AccessoryTextView) {
        guard textView.shouldAutofocus else {
            NotesEditEntryDebugTrace.log(
                "scheduleAutofocusIfNeeded.skip",
                details: "reason=shouldAutofocusFalse " + NotesEditEntryDebugTrace.textViewSummary(textView)
            )
            return
        }
        guard textView.window != nil else {
            NotesEditEntryDebugTrace.log(
                "scheduleAutofocusIfNeeded.skip",
                details: "reason=noWindow " + NotesEditEntryDebugTrace.textViewSummary(textView)
            )
            return
        }
        guard !textView.isFirstResponder else {
            NotesEditEntryDebugTrace.log(
                "scheduleAutofocusIfNeeded.skip",
                details: "reason=alreadyFirstResponder " + NotesEditEntryDebugTrace.textViewSummary(textView)
            )
            return
        }
        guard !textView.hasScheduledAutofocus else {
            NotesEditEntryDebugTrace.log(
                "scheduleAutofocusIfNeeded.skip",
                details: "reason=alreadyScheduled " + NotesEditEntryDebugTrace.textViewSummary(textView)
            )
            return
        }
        NotesEditEntryDebugTrace.log(
            "scheduleAutofocusIfNeeded.schedule",
            details: NotesEditEntryDebugTrace.textViewSummary(textView)
        )
        textView.hasScheduledAutofocus = true
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            defer { textView.hasScheduledAutofocus = false }
            guard textView.shouldAutofocus, textView.window != nil else {
                NotesEditEntryDebugTrace.log(
                    "scheduleAutofocusIfNeeded.cancel",
                    details: NotesEditEntryDebugTrace.textViewSummary(textView)
                )
                return
            }
            guard !textView.isFirstResponder else { return }
            NotesEditEntryDebugTrace.log(
                "scheduleAutofocusIfNeeded.becomeFirstResponder.begin",
                details: NotesEditEntryDebugTrace.textViewSummary(textView)
            )
            textView.window?.makeKey()
            let didBecomeFirstResponder = textView.becomeFirstResponder()
            NotesEditEntryDebugTrace.log(
                "scheduleAutofocusIfNeeded.becomeFirstResponder.end",
                details:
                    "didBecomeFirstResponder=\(didBecomeFirstResponder) "
                    + NotesEditEntryDebugTrace.textViewSummary(textView)
            )
        }
    }

    func acknowledgePendingSelectionTargetIfNeeded(
        _ pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?,
        selectedRange: NSRange,
        textView: AccessoryTextView,
        coordinator: Coordinator
    ) {
        let document = viewModel.currentPersistenceSnapshot().document
        let displaySelectedRange = SelectableNoteReadView.editorDisplaySelectedRange(
            in: document,
            logicalSelectedRange: selectedRange
        )
        guard let pendingSelectionTarget, textView.selectedRange == displaySelectedRange else {
            coordinator.acknowledgedPendingSelectionTarget = nil
            return
        }
        guard coordinator.acknowledgedPendingSelectionTarget != pendingSelectionTarget else { return }
        coordinator.acknowledgedPendingSelectionTarget = pendingSelectionTarget
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            if textView.selectedRange == displaySelectedRange {
                let logicalRange = SelectableNoteReadView.logicalEditorSelectedRange(
                    fromDisplaySelectedRange: textView.selectedRange,
                    in: textView.attributedText
                )
                let selection = viewModel.selection(
                    fromUTF16Range: logicalRange,
                    in: viewModel.attributedContent
                )
                if selection != viewModel.selection {
                    viewModel.selection = selection
                    viewModel.handleSelectionChange()
                }
            }
            onPendingSelectionTargetApplied?(textView)
        }
    }

    func configureFormattingUI(
        for textView: AccessoryTextView,
        configuration: NoteFormattingBarConfiguration?
    ) -> Bool {
        textView.formattingCommandsEnabled = configuration?.isEnabled ?? false
        textView.onTitleCommand = configuration?.onTitleShortcut
        textView.onHeadingCommand = configuration?.onHeadingShortcut
        textView.onSubheadingCommand = configuration?.onSubheadingShortcut
        textView.onBodyCommand = configuration?.onBodyShortcut
        textView.onBoldCommand = configuration?.onBoldTap
        textView.onItalicCommand = configuration?.onItalicTap
        textView.onUnderlineCommand = configuration?.onUnderlineTap

        guard shouldShowFormattingAccessory else {
            if textView.formattingAccessoryView != nil {
                textView.formattingAccessoryView = nil
                return true
            }
            return false
        }

        switch (textView.formattingAccessoryView as? UIKitNoteFormattingAccessoryView, configuration) {
        case let (accessoryView?, configuration?):
            accessoryView.apply(
                configuration: configuration,
                presentation: formattingBarPresentation
            )
            return false
        case (nil, let configuration?):
            textView.formattingAccessoryView = makeFormattingAccessoryView(
                configuration: configuration
            )
            return true
        case (_?, nil):
            textView.formattingAccessoryView = nil
            return true
        case (nil, nil):
            return false
        }
    }

    func makeFormattingAccessoryView(
        configuration: NoteFormattingBarConfiguration
    ) -> UIKitNoteFormattingAccessoryView {
        let accessoryView = UIKitNoteFormattingAccessoryView(
            configuration: configuration,
            presentation: formattingBarPresentation
        )
        accessoryView.autoresizingMask = [.flexibleWidth]
        return accessoryView
    }

    var shouldShowFormattingAccessory: Bool {
        isEditable && formattingBarPresentation == .keyboardAccessory
    }

    func resolvedSelectedRange(
        pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?,
        textView: UITextView,
        coordinator: Coordinator
    ) -> NSRange {
        if let pendingSelectionTarget {
            if coordinator.acknowledgedPendingSelectionTarget == pendingSelectionTarget {
                return textView.selectedRange
            }
            return pendingSelectedRange(for: pendingSelectionTarget, in: viewModel.attributedContent)
        }
        return viewModel.utf16SelectedRange(in: viewModel.attributedContent)
    }

    func pendingSelectedRange(
        for target: NotesEditorViewModel.PendingEditSelectionTarget,
        in text: AttributedString
    ) -> NSRange {
        switch target {
        case .start:
            return NSRange(location: 0, length: 0)
        case .characterOffset(let offset):
            let index = viewModel.index(forUTF16Offset: offset, in: text)
            let utf16Offset = viewModel.utf16Offset(for: index, in: text)
            return NSRange(location: utf16Offset, length: 0)
        }
    }
}
#endif
