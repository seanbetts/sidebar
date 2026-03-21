#if os(iOS)
import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct UIKitNoteTextEditorSurface: UIViewRepresentable {
    fileprivate struct RenderSignature: Equatable {
        let renderGeneration: UInt64
        let baseFontSize: CGFloat
    }

    class AccessoryTextView: UITextView {
        static let baseTextContainerInsets = UIEdgeInsets(
            top: NoteTextLayout.verticalPadding, left: NoteTextLayout.horizontalPadding,
            bottom: NoteTextLayout.verticalPadding, right: NoteTextLayout.horizontalPadding
        )

        var formattingAccessoryView: UIView?
        var formattingCommandsEnabled = false
        var onBoldCommand: (() -> Void)?
        var onItalicCommand: (() -> Void)?
        var onUnderlineCommand: (() -> Void)?
        var onTitleCommand: (() -> Void)?
        var onHeadingCommand: (() -> Void)?
        var onSubheadingCommand: (() -> Void)?
        var onBodyCommand: (() -> Void)?
        var shouldAutofocus = false
        var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
            didSet { setNeedsLayout() }
        }
        var pendingInitialViewportOffset: CGPoint? {
            didSet {
                guard pendingInitialViewportOffset != oldValue else { return }
                hasAppliedPendingInitialViewportOffset = false
                initialViewportVerificationPassesRemaining = pendingInitialViewportOffset == nil ? 0 : 8
                schedulePendingInitialViewportRetryBurst()
                scheduleInitialViewportVerificationIfNeeded()
                applyPendingInitialViewportOffsetIfNeeded()
            }
        }
        var keyboardObservers: [NSObjectProtocol] = []
        var keyboardFrameInScreen: CGRect?
        var hasAppliedPendingInitialViewportOffset = false
        var initialViewportVerificationPassesRemaining = 0
        var isInitialViewportVerificationScheduled = false
        var selectionChangeAdjustmentGeneration = 0
        var deferredViewportRestorationGeneration = 0
        var directTouchSelectionChangeDeadline: CFTimeInterval = 0
        var lastStableSelectionRange = NSRange(location: NSNotFound, length: 0)
        var lastStableViewportOffset = CGPoint.zero
        var debugHasAppliedPendingInitialViewportOffset: Bool { hasAppliedPendingInitialViewportOffset }
        var debugPendingInitialViewportOffset: CGPoint? { pendingInitialViewportOffset }
        override var contentSize: CGSize {
            didSet {
                applyPendingInitialViewportOffsetIfNeeded()
                scheduleInitialViewportVerificationIfNeeded()
            }
        }

        override var inputAccessoryView: UIView? {
            get { formattingAccessoryView }
            set { formattingAccessoryView = newValue }
        }

        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            super.setContentOffset(contentOffset, animated: animated)
            guard selectedRange == lastStableSelectionRange else { return }
            lastStableViewportOffset = self.contentOffset
        }

        override var keyCommands: [UIKeyCommand]? {
            guard formattingCommandsEnabled else { return super.keyCommands }
            return [
                UIKeyCommand(input: "t", modifierFlags: [.command, .shift], action: #selector(handleTitleCommand)),
                UIKeyCommand(input: "h", modifierFlags: [.command, .shift], action: #selector(handleHeadingCommand)),
                UIKeyCommand(input: "j", modifierFlags: [.command, .shift], action: #selector(handleSubheadingCommand)),
                UIKeyCommand(input: "b", modifierFlags: [.command, .shift], action: #selector(handleBodyCommand)),
                UIKeyCommand(input: "b", modifierFlags: [.command], action: #selector(handleBoldCommand)),
                UIKeyCommand(input: "i", modifierFlags: [.command], action: #selector(handleItalicCommand)),
                UIKeyCommand(input: "u", modifierFlags: [.command], action: #selector(handleUnderlineCommand))
            ]
        }

        @objc private func handleTitleCommand() { onTitleCommand?() }
        @objc private func handleHeadingCommand() { onHeadingCommand?() }
        @objc private func handleSubheadingCommand() { onSubheadingCommand?() }
        @objc private func handleBodyCommand() { onBodyCommand?() }
        @objc private func handleBoldCommand() { onBoldCommand?() }
        @objc private func handleItalicCommand() { onItalicCommand?() }
        @objc private func handleUnderlineCommand() { onUnderlineCommand?() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateKeyboardObservation()
            applyPendingInitialViewportOffsetIfNeeded()
            guard shouldAutofocus, window != nil, isFirstResponder == false else { return }
            scheduleAutofocusRetryBurst()
        }

        override func becomeFirstResponder() -> Bool {
            let becameFirstResponder = super.becomeFirstResponder()
            guard becameFirstResponder else { return false }
            DispatchQueue.main.async { [weak self] in
                self?.applyPendingInitialViewportOffsetIfNeeded()
            }
            return true
        }

        deinit {
            removeKeyboardObservers()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateTextContainerInsets()
            updateViewportInsets()
            applyPendingInitialViewportOffsetIfNeeded()
            scheduleInitialViewportVerificationIfNeeded()
        }

        private func schedulePendingInitialViewportRetryBurst() {
            guard let pendingInitialViewportOffset else { return }
            for delay in [0.0, 0.01, 0.05] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.pendingInitialViewportOffset == pendingInitialViewportOffset else {
                        return
                    }
                    self.applyPendingInitialViewportOffsetIfNeeded()
                }
            }
        }

        func scheduleAutofocusRetryBurst() {
            for delay in [0.0, 0.01, 0.05, 0.1, 0.2, 0.35, 0.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self,
                          self.shouldAutofocus,
                          self.window != nil,
                          self.isFirstResponder == false else {
                        return
                    }
                    self.window?.makeKey()
                    self.window?.endEditing(false)
                    _ = self.becomeFirstResponder()
                }
            }
        }

    }

    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let shouldAutofocus: Bool
    let formattingBarConfiguration: NoteFormattingBarConfiguration?
    let formattingBarPresentation: NoteFormattingBarPresentation
    let initialViewportOffset: CGPoint?
    let makeTextView: (() -> AccessoryTextView)?

    init(
        viewModel: NativeNoteEditorViewModel,
        maxContentWidth: CGFloat,
        isEditable: Bool,
        shouldAutofocus: Bool = true,
        formattingBarConfiguration: NoteFormattingBarConfiguration? = nil,
        formattingBarPresentation: NoteFormattingBarPresentation,
        initialViewportOffset: CGPoint? = nil,
        makeTextView: (() -> AccessoryTextView)? = nil
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.isEditable = isEditable
        self.shouldAutofocus = shouldAutofocus
        self.formattingBarConfiguration = formattingBarConfiguration
        self.formattingBarPresentation = formattingBarPresentation
        self.initialViewportOffset = initialViewportOffset
        self.makeTextView = makeTextView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> UITextView {
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
        textView.delegate = context.coordinator
        textView.textFormattingConfiguration = nil
        if shouldShowFormattingAccessory, let formattingBarConfiguration {
            textView.formattingAccessoryView = makeFormattingAccessoryView(
                configuration: formattingBarConfiguration
            )
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = isEditable
        if let accessoryTextView = textView as? AccessoryTextView {
            accessoryTextView.shouldAutofocus = isEditable && shouldAutofocus
            accessoryTextView.maxReadableContentWidth = maxContentWidth
            accessoryTextView.updatePendingInitialViewportOffset(initialViewportOffset)
            if isEditable, shouldAutofocus, accessoryTextView.window != nil, accessoryTextView.isFirstResponder == false {
                DispatchQueue.main.async {
                    accessoryTextView.scheduleAutofocusRetryBurst()
                }
            }
            let needsAccessoryReload = configureFormattingUI(
                for: accessoryTextView,
                configuration: formattingBarConfiguration
            )
            if needsAccessoryReload, accessoryTextView.isFirstResponder {
                accessoryTextView.reloadInputViews()
            }
        }
        let renderSignature = RenderSignature(
            renderGeneration: viewModel.renderGeneration,
            baseFontSize: viewModel.baseFontSize
        )
        let selectedRange = viewModel.utf16SelectedRange(in: viewModel.attributedContent)
        let isProgrammaticRenderUpdate = context.coordinator.lastAppliedRenderSignature != renderSignature
        let preservedViewportOffset = preservedViewportOffsetIfNeeded(
            for: textView,
            selectedRange: selectedRange,
            preserveAcrossSelectionChange: isProgrammaticRenderUpdate
        )
        if isProgrammaticRenderUpdate {
            let attributedText = bridgedAttributedText(from: viewModel.attributedContent)
            context.coordinator.isApplyingProgrammaticText = true
            textView.attributedText = attributedText
            context.coordinator.isApplyingProgrammaticText = false
            context.coordinator.lastAppliedRenderSignature = renderSignature
        }

        if textView.selectedRange != selectedRange {
            context.coordinator.isApplyingProgrammaticSelection = true
            textView.selectedRange = selectedRange
            context.coordinator.isApplyingProgrammaticSelection = false
        }

        let typingAttributes = bridgedTypingAttributes(from: viewModel.attributedContent)
        if NSDictionary(dictionary: textView.typingAttributes).isEqual(to: typingAttributes) == false {
            textView.typingAttributes = typingAttributes
        }

        if let preservedViewportOffset {
            restoreViewportOffsetIfNeeded(
                preservedViewportOffset,
                for: textView,
                selectedRange: selectedRange
            )
        }
        if let accessoryTextView = textView as? AccessoryTextView {
            accessoryTextView.applyPendingInitialViewportOffsetIfNeeded()
            if accessoryTextView.pendingInitialViewportOffset != nil {
                DispatchQueue.main.async { [weak accessoryTextView] in
                    accessoryTextView?.applyPendingInitialViewportOffsetIfNeeded()
                }
            }
        }
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Void) {
        if textView.isFirstResponder {
            textView.resignFirstResponder()
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

    private func configureFormattingUI(
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

    private func makeFormattingAccessoryView(
        configuration: NoteFormattingBarConfiguration
    ) -> UIKitNoteFormattingAccessoryView {
        let accessoryView = UIKitNoteFormattingAccessoryView(
            configuration: configuration,
            presentation: formattingBarPresentation
        )
        accessoryView.autoresizingMask = [.flexibleWidth]
        return accessoryView
    }

    private var shouldShowFormattingAccessory: Bool {
        isEditable && formattingBarPresentation == .keyboardAccessory
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let viewModel: NativeNoteEditorViewModel
        var isApplyingProgrammaticText = false, isApplyingProgrammaticSelection = false
        fileprivate var lastAppliedRenderSignature: RenderSignature?

        init(viewModel: NativeNoteEditorViewModel) {
            self.viewModel = viewModel
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticText else { return }

            isApplyingProgrammaticText = true
            viewModel.replaceAttributedContent(
                textView.attributedText,
                selectedUTF16Range: textView.selectedRange
            )
            isApplyingProgrammaticText = false
            lastAppliedRenderSignature = RenderSignature(
                renderGeneration: viewModel.renderGeneration,
                baseFontSize: viewModel.baseFontSize
            )
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticText, !isApplyingProgrammaticSelection else { return }

            let selection = viewModel.selection(
                fromUTF16Range: textView.selectedRange,
                in: viewModel.attributedContent
            )
            if selection != viewModel.selection {
                viewModel.selection = selection
                viewModel.handleSelectionChange()
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            let selection = viewModel.selection(fromUTF16Range: range, in: viewModel.attributedContent)
            if selection != viewModel.selection {
                viewModel.selection = selection
                viewModel.handleSelectionChange()
            }

            guard text.contains("\n") else { return true }
            guard viewModel.handleTextReplacement(text) else { return true }

            applyCurrentEditorState(to: textView)
            return false
        }

        private func applyCurrentEditorState(to textView: UITextView) {
            let bridgedText = SelectableNoteReadView.bridgedPlatformAttributedString(
                from: viewModel.attributedContent,
                baseFontSize: viewModel.baseFontSize
            )
            isApplyingProgrammaticText = true
            textView.attributedText = bridgedText
            isApplyingProgrammaticText = false
            lastAppliedRenderSignature = RenderSignature(
                renderGeneration: viewModel.renderGeneration,
                baseFontSize: viewModel.baseFontSize
            )

            isApplyingProgrammaticSelection = true
            textView.selectedRange = viewModel.utf16SelectedRange(in: viewModel.attributedContent)
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
    }
}

#endif
