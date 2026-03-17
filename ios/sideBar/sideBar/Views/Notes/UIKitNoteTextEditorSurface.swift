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
        private static let baseTextContainerInsets = UIEdgeInsets(
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
        private var keyboardObservers: [NSObjectProtocol] = []
        private var keyboardFrameInScreen: CGRect?

        override var inputAccessoryView: UIView? {
            get { formattingAccessoryView }
            set { formattingAccessoryView = newValue }
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

        @objc private func handleTitleCommand() {
            onTitleCommand?()
        }

        @objc private func handleHeadingCommand() {
            onHeadingCommand?()
        }

        @objc private func handleSubheadingCommand() {
            onSubheadingCommand?()
        }

        @objc private func handleBodyCommand() {
            onBodyCommand?()
        }

        @objc private func handleBoldCommand() {
            onBoldCommand?()
        }

        @objc private func handleItalicCommand() {
            onItalicCommand?()
        }

        @objc private func handleUnderlineCommand() {
            onUnderlineCommand?()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateKeyboardObservation()
            guard shouldAutofocus, window != nil, isFirstResponder == false else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.isFirstResponder == false else { return }
                self.becomeFirstResponder()
            }
        }

        deinit {
            removeKeyboardObservers()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateTextContainerInsets()
            updateViewportInsets()
        }

        private func updateKeyboardObservation() {
            removeKeyboardObservers()
            guard window != nil else {
                keyboardFrameInScreen = nil
                updateViewportInsets()
                return
            }

            let center = NotificationCenter.default
            keyboardObservers = [
                center.addObserver(
                    forName: UIResponder.keyboardWillChangeFrameNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleKeyboardNotification(notification)
                },
                center.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.keyboardFrameInScreen = nil
                    self?.updateViewportInsets()
                }
            ]
            updateViewportInsets()
        }

        private func removeKeyboardObservers() {
            let center = NotificationCenter.default
            keyboardObservers.forEach(center.removeObserver)
            keyboardObservers.removeAll()
        }

        private func handleKeyboardNotification(_ notification: Notification) {
            guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
                return
            }
            keyboardFrameInScreen = frameValue.cgRectValue
            updateViewportInsets()
        }

        private func updateViewportInsets() {
            let bottomInset = UIKitNoteTextEditorSurface.resolvedBottomViewportInset(
                textViewBounds: bounds,
                keyboardFrameInView: resolvedKeyboardFrameInView(),
                accessoryHeight: resolvedAccessoryHeight()
            )
            let previousBottomInset = contentInset.bottom
            contentInset.bottom = bottomInset
            var indicatorInsets = verticalScrollIndicatorInsets
            indicatorInsets.bottom = bottomInset
            verticalScrollIndicatorInsets = indicatorInsets

            guard abs(previousBottomInset - bottomInset) > 0.5 else { return }
            scrollCurrentSelectionIntoView()
        }

        private func updateTextContainerInsets() {
            let extraHorizontalInset = max((bounds.width - maxReadableContentWidth) / 2, 0)
            let resolvedInsets = UIEdgeInsets(
                top: Self.baseTextContainerInsets.top,
                left: Self.baseTextContainerInsets.left + extraHorizontalInset,
                bottom: Self.baseTextContainerInsets.bottom,
                right: Self.baseTextContainerInsets.right + extraHorizontalInset
            )
            guard textContainerInset != resolvedInsets else { return }
            textContainerInset = resolvedInsets
        }

        private func resolvedKeyboardFrameInView() -> CGRect? {
            guard let keyboardFrameInScreen,
                  let window else { return nil }
            let keyboardFrameInWindow = window.convert(keyboardFrameInScreen, from: nil)
            return convert(keyboardFrameInWindow, from: window)
        }

        private func resolvedAccessoryHeight() -> CGFloat {
            guard formattingAccessoryView != nil, isFirstResponder else { return 0 }
            return formattingAccessoryView?.bounds.height ?? 0
        }

        fileprivate func scrollCurrentSelectionIntoView() {
            guard selectedRange.location != NSNotFound else { return }
            scrollRangeToVisible(selectedRange)
        }
    }

    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let shouldAutofocus: Bool
    let formattingBarConfiguration: NoteFormattingBarConfiguration?
    let formattingBarPresentation: NoteFormattingBarPresentation
    let makeTextView: (() -> AccessoryTextView)?

    init(
        viewModel: NativeNoteEditorViewModel,
        maxContentWidth: CGFloat,
        isEditable: Bool,
        shouldAutofocus: Bool = true,
        formattingBarConfiguration: NoteFormattingBarConfiguration? = nil,
        formattingBarPresentation: NoteFormattingBarPresentation,
        makeTextView: (() -> AccessoryTextView)? = nil
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.isEditable = isEditable
        self.shouldAutofocus = shouldAutofocus
        self.formattingBarConfiguration = formattingBarConfiguration
        self.formattingBarPresentation = formattingBarPresentation
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
            if isEditable, shouldAutofocus, accessoryTextView.window != nil, accessoryTextView.isFirstResponder == false {
                DispatchQueue.main.async {
                    accessoryTextView.becomeFirstResponder()
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
        if context.coordinator.lastAppliedRenderSignature != renderSignature {
            let attributedText = bridgedAttributedText(from: viewModel.attributedContent)
            context.coordinator.isApplyingProgrammaticText = true
            textView.attributedText = attributedText
            context.coordinator.isApplyingProgrammaticText = false
            context.coordinator.lastAppliedRenderSignature = renderSignature
        }

        let selectedRange = viewModel.utf16SelectedRange(in: viewModel.attributedContent)
        if textView.selectedRange != selectedRange {
            context.coordinator.isApplyingProgrammaticSelection = true
            textView.selectedRange = selectedRange
            context.coordinator.isApplyingProgrammaticSelection = false
        }

        let typingAttributes = bridgedTypingAttributes(from: viewModel.attributedContent)
        if NSDictionary(dictionary: textView.typingAttributes).isEqual(to: typingAttributes) == false {
            textView.typingAttributes = typingAttributes
        }
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Void) {
        if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    static func resolvedBottomViewportInset(
        textViewBounds: CGRect,
        keyboardFrameInView: CGRect?,
        accessoryHeight: CGFloat
    ) -> CGFloat {
        guard let keyboardFrameInView,
              keyboardFrameInView.intersects(textViewBounds) else {
            return 0
        }

        let overlap = max(textViewBounds.maxY - keyboardFrameInView.minY, 0)
        return max(overlap + accessoryHeight, 0)
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
        var isApplyingProgrammaticText = false
        var isApplyingProgrammaticSelection = false
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
            guard !isApplyingProgrammaticText else { return }
            guard !isApplyingProgrammaticSelection else { return }

            let selection = viewModel.selection(
                fromUTF16Range: textView.selectedRange,
                in: viewModel.attributedContent
            )
            guard selection != viewModel.selection else { return }
            viewModel.selection = selection
            viewModel.handleSelectionChange()
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
