#if os(iOS)
import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct UIKitNoteTextEditorSurface: UIViewRepresentable {
    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = isEditable
        textView.backgroundColor = .clear
        textView.accessibilityIdentifier = "notes-editor-text-view"
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = isEditable
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
