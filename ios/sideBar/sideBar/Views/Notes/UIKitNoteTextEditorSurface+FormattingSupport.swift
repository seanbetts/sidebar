#if os(iOS)
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface {
    func scheduleAutofocusIfNeeded(for textView: AccessoryTextView) {
        guard textView.shouldAutofocus,
              textView.window != nil,
              !textView.isFirstResponder,
              !textView.hasScheduledAutofocus else {
            return
        }
        textView.hasScheduledAutofocus = true
        NotesIOSDebugTrace.log("UIKitNoteTextEditorSurface.scheduleAutofocusIfNeeded.enqueue", textView: textView)
        DispatchQueue.main.async { [weak textView] in
            guard let textView, textView.shouldAutofocus, textView.window != nil else { return }
            textView.hasScheduledAutofocus = false
            guard !textView.isFirstResponder else { return }
            NotesIOSDebugTrace.log("UIKitNoteTextEditorSurface.scheduleAutofocusIfNeeded.fire.begin", textView: textView)
            textView.window?.makeKey()
            let becameFirstResponder = textView.becomeFirstResponder()
            NotesIOSDebugTrace.log(
                "UIKitNoteTextEditorSurface.scheduleAutofocusIfNeeded.fire.end",
                textView: textView,
                extras: [
                    "becameFirstResponder": "\(becameFirstResponder)"
                ]
            )
        }
    }

    func acknowledgePendingSelectionTargetIfNeeded(
        _ pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?,
        selectedRange: NSRange,
        textView: AccessoryTextView,
        coordinator: Coordinator
    ) {
        guard let pendingSelectionTarget, textView.selectedRange == selectedRange else {
            coordinator.acknowledgedPendingSelectionTarget = nil
            return
        }
        guard coordinator.acknowledgedPendingSelectionTarget != pendingSelectionTarget else { return }
        coordinator.acknowledgedPendingSelectionTarget = pendingSelectionTarget
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            if textView.selectedRange == selectedRange {
                let selection = viewModel.selection(
                    fromUTF16Range: selectedRange,
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
