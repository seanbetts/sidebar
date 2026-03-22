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
        var hasScheduledAutofocus = false
        var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
            didSet { setNeedsLayout() }
        }
        var debugPendingInitialViewportOffset: CGPoint? { nil }

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

        @objc private func handleTitleCommand() { onTitleCommand?() }
        @objc private func handleHeadingCommand() { onHeadingCommand?() }
        @objc private func handleSubheadingCommand() { onSubheadingCommand?() }
        @objc private func handleBodyCommand() { onBodyCommand?() }
        @objc private func handleBoldCommand() { onBoldCommand?() }
        @objc private func handleItalicCommand() { onItalicCommand?() }
        @objc private func handleUnderlineCommand() { onUnderlineCommand?() }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateTextContainerInsets()
            updateViewportInsets()
        }

    }

    final class EditorContainerView: UIView {
        let textView: AccessoryTextView

        init(textView: AccessoryTextView) {
            self.textView = textView
            super.init(frame: .zero)
            backgroundColor = .clear
            textView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textView)
            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let shouldAutofocus: Bool
    let formattingBarConfiguration: NoteFormattingBarConfiguration?
    let formattingBarPresentation: NoteFormattingBarPresentation
    let pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?
    let onPendingSelectionTargetApplied: ((AccessoryTextView) -> Void)?
    let onDidBeginEditing: ((AccessoryTextView) -> Void)?
    let makeTextView: (() -> AccessoryTextView)?

    init(
        viewModel: NativeNoteEditorViewModel,
        maxContentWidth: CGFloat,
        isEditable: Bool,
        shouldAutofocus: Bool = true,
        formattingBarConfiguration: NoteFormattingBarConfiguration? = nil,
        formattingBarPresentation: NoteFormattingBarPresentation,
        pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget? = nil,
        onPendingSelectionTargetApplied: ((AccessoryTextView) -> Void)? = nil,
        onDidBeginEditing: ((AccessoryTextView) -> Void)? = nil,
        makeTextView: (() -> AccessoryTextView)? = nil
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.isEditable = isEditable
        self.shouldAutofocus = shouldAutofocus
        self.formattingBarConfiguration = formattingBarConfiguration
        self.formattingBarPresentation = formattingBarPresentation
        self.pendingSelectionTarget = pendingSelectionTarget
        self.onPendingSelectionTargetApplied = onPendingSelectionTargetApplied
        self.onDidBeginEditing = onDidBeginEditing
        self.makeTextView = makeTextView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> EditorContainerView {
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
        return EditorContainerView(textView: textView)
    }

    func updateUIView(_ containerView: EditorContainerView, context: Context) {
        let textView = containerView.textView
        context.coordinator.onDidBeginEditing = onDidBeginEditing
        textView.isEditable = isEditable
        textView.shouldAutofocus = isEditable && shouldAutofocus
        textView.maxReadableContentWidth = maxContentWidth
        let needsAccessoryReload = configureFormattingUI(
            for: textView,
            configuration: formattingBarConfiguration
        )
        if needsAccessoryReload, textView.isFirstResponder {
            textView.reloadInputViews()
        }
        let renderSignature = RenderSignature(
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

    static func dismantleUIView(_ containerView: EditorContainerView, coordinator: Void) {
        let textView = containerView.textView
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

    private func applyRenderedTextIfNeeded(
        to textView: AccessoryTextView,
        coordinator: Coordinator,
        renderSignature: RenderSignature,
        isProgrammaticRenderUpdate: Bool
    ) {
        guard isProgrammaticRenderUpdate else { return }
        let preservedContentOffset = viewModel.consumeViewportPreservationOnNextProgrammaticRender() ?
            textView.contentOffset : nil
        let attributedText = bridgedAttributedText(from: viewModel.attributedContent)
        coordinator.isApplyingProgrammaticText = true
        textView.textStorage.setAttributedString(attributedText)
        coordinator.isApplyingProgrammaticText = false
        if let preservedContentOffset {
            textView.layoutIfNeeded()
            textView.setContentOffset(
                Self.clampedContentOffset(preservedContentOffset, for: textView),
                animated: false
            )
        }
        coordinator.lastAppliedRenderSignature = renderSignature
    }

    private func applySelectionIfNeeded(
        to textView: AccessoryTextView,
        coordinator: Coordinator,
        selectedRange: NSRange
    ) {
        guard textView.selectedRange != selectedRange else { return }
        coordinator.isApplyingProgrammaticSelection = true
        textView.selectedRange = selectedRange
        coordinator.isApplyingProgrammaticSelection = false
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let viewModel: NativeNoteEditorViewModel
        var isApplyingProgrammaticText = false, isApplyingProgrammaticSelection = false
        fileprivate var lastAppliedRenderSignature: RenderSignature?
        var acknowledgedPendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        var onDidBeginEditing: ((AccessoryTextView) -> Void)?

        init(viewModel: NativeNoteEditorViewModel) {
            self.viewModel = viewModel
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticText else { return }

            isApplyingProgrammaticText = true
            viewModel.replaceAttributedContentFromLiveTextView(
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

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard let textView = textView as? AccessoryTextView else { return }
            onDidBeginEditing?(textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard viewModel.shouldHandleStructuralTextReplacement(text) else { return true }

            let selection = viewModel.selection(fromUTF16Range: range, in: viewModel.attributedContent)
            if selection != viewModel.selection {
                viewModel.selection = selection
                viewModel.handleSelectionChange()
            }

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
            textView.textStorage.setAttributedString(bridgedText)
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

@available(iOS 26.0, *)
private extension UIKitNoteTextEditorSurface {
    func scheduleAutofocusIfNeeded(for textView: AccessoryTextView) {
        guard textView.shouldAutofocus,
              textView.window != nil,
              !textView.isFirstResponder,
              !textView.hasScheduledAutofocus else {
            return
        }
        textView.hasScheduledAutofocus = true
        DispatchQueue.main.async { [weak textView] in
            guard let textView, textView.shouldAutofocus, textView.window != nil else { return }
            textView.hasScheduledAutofocus = false
            guard !textView.isFirstResponder else { return }
            textView.window?.makeKey()
            _ = textView.becomeFirstResponder()
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
