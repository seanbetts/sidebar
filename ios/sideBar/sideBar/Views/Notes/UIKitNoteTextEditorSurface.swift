#if os(iOS)
import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct UIKitNoteTextEditorSurface: UIViewRepresentable {
    final class AccessoryTextView: UITextView {
        var formattingAccessoryView: UIView?
        var formattingCommandsEnabled = false
        var onBoldCommand: (() -> Void)?
        var onItalicCommand: (() -> Void)?
        var onUnderlineCommand: (() -> Void)?

        override var inputAccessoryView: UIView? {
            get { formattingAccessoryView }
            set { formattingAccessoryView = newValue }
        }

        override var keyCommands: [UIKeyCommand]? {
            guard formattingCommandsEnabled else { return super.keyCommands }
            return [
                UIKeyCommand(input: "b", modifierFlags: [.command], action: #selector(handleBoldCommand)),
                UIKeyCommand(input: "i", modifierFlags: [.command], action: #selector(handleItalicCommand)),
                UIKeyCommand(input: "u", modifierFlags: [.command], action: #selector(handleUnderlineCommand))
            ]
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
    }

    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let formattingBarConfiguration: UIKitNoteFormattingBar.Configuration?

    init(
        viewModel: NativeNoteEditorViewModel,
        maxContentWidth: CGFloat,
        isEditable: Bool,
        formattingBarConfiguration: UIKitNoteFormattingBar.Configuration? = nil
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.isEditable = isEditable
        self.formattingBarConfiguration = formattingBarConfiguration
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = AccessoryTextView()
        textView.isEditable = isEditable
        textView.allowsEditingTextAttributes = true
        textView.backgroundColor = .clear
        textView.accessibilityIdentifier = "notes-editor-text-view"
        textView.delegate = context.coordinator
        textView.textFormattingConfiguration = nil
        if let formattingBarConfiguration {
            textView.formattingAccessoryView = makeFormattingBar(configuration: formattingBarConfiguration)
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = isEditable
        if let accessoryTextView = textView as? AccessoryTextView {
            let needsAccessoryReload = configureAccessoryView(
                for: accessoryTextView,
                configuration: formattingBarConfiguration
            )
            if needsAccessoryReload, accessoryTextView.isFirstResponder {
                accessoryTextView.reloadInputViews()
            }
        }
        let attributedText = bridgedAttributedText(from: viewModel.attributedContent)
        if textView.attributedText.isEqual(to: attributedText) == false {
            context.coordinator.isApplyingProgrammaticText = true
            textView.attributedText = attributedText
            context.coordinator.isApplyingProgrammaticText = false
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

    private func bridgedAttributedText(from text: AttributedString) -> NSAttributedString {
        SelectableNoteReadView.bridgedPlatformAttributedString(
            from: text,
            baseFontSize: viewModel.baseFontSize
        )
    }

    private func bridgedTypingAttributes(from text: AttributedString) -> [NSAttributedString.Key: Any] {
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(viewModel.selection.typingAttributes(in: text))
        let bridged = SelectableNoteReadView.bridgedPlatformAttributedString(
            from: sample,
            baseFontSize: viewModel.baseFontSize
        )
        return bridged.attributes(at: 0, effectiveRange: nil)
    }

    private func configureAccessoryView(
        for textView: AccessoryTextView,
        configuration: UIKitNoteFormattingBar.Configuration?
    ) -> Bool {
        switch (textView.formattingAccessoryView as? UIKitNoteFormattingBar, configuration) {
        case let (bar?, configuration?):
            bar.apply(configuration: configuration)
            textView.formattingCommandsEnabled = configuration.isEnabled
            textView.onBoldCommand = configuration.onBoldTap
            textView.onItalicCommand = configuration.onItalicTap
            textView.onUnderlineCommand = configuration.onUnderlineTap
            return false
        case (nil, let configuration?):
            textView.formattingAccessoryView = makeFormattingBar(configuration: configuration)
            textView.formattingCommandsEnabled = configuration.isEnabled
            textView.onBoldCommand = configuration.onBoldTap
            textView.onItalicCommand = configuration.onItalicTap
            textView.onUnderlineCommand = configuration.onUnderlineTap
            return true
        case (_?, nil):
            textView.formattingAccessoryView = nil
            textView.formattingCommandsEnabled = false
            textView.onBoldCommand = nil
            textView.onItalicCommand = nil
            textView.onUnderlineCommand = nil
            return true
        case (nil, nil):
            textView.formattingCommandsEnabled = false
            textView.onBoldCommand = nil
            textView.onItalicCommand = nil
            textView.onUnderlineCommand = nil
            return false
        }
    }

    private func makeFormattingBar(
        configuration: UIKitNoteFormattingBar.Configuration
    ) -> UIKitNoteFormattingBar {
        let bar = UIKitNoteFormattingBar(configuration: configuration)
        bar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return bar
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let viewModel: NativeNoteEditorViewModel
        var isApplyingProgrammaticText = false
        var isApplyingProgrammaticSelection = false

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
    }
}
#endif
