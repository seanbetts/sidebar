#if os(iOS)
import SwiftUI
import UIKit

@available(iOS 26.0, *)
enum NoteFormattingBarPresentationMode: Equatable {
    case accessoryBar
    case anchoredBar
}

@available(iOS 26.0, *)
struct UIKitNoteTextEditorSurface: View {
    @Binding var attributedContent: AttributedString
    @Binding var selection: AttributedTextSelection
    let maxContentWidth: CGFloat
    let baseFontSize: CGFloat
    let isEditable: Bool
    let shouldFocus: Bool
    let formattingBarPresentationMode: NoteFormattingBarPresentationMode

    var body: some View {
        NoteEditorTextViewRepresentable(
            attributedContent: $attributedContent,
            selection: $selection,
            baseFontSize: baseFontSize,
            isEditable: isEditable,
            shouldFocus: shouldFocus,
            formattingBarPresentationMode: formattingBarPresentationMode
        )
        .padding(.horizontal, NoteTextLayout.horizontalPadding)
        .padding(.vertical, NoteTextLayout.verticalPadding)
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
    }
}

@available(iOS 26.0, *)
private struct NoteEditorTextViewRepresentable: UIViewRepresentable {
    @Binding var attributedContent: AttributedString
    @Binding var selection: AttributedTextSelection
    let baseFontSize: CGFloat
    let isEditable: Bool
    let shouldFocus: Bool
    let formattingBarPresentationMode: NoteFormattingBarPresentationMode

    func makeUIView(context: Context) -> NoteEditorTextView {
        let textView = NoteEditorTextView()
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(
            top: NoteTextLayout.verticalPadding,
            left: 0,
            bottom: NoteTextLayout.verticalPadding,
            right: 0
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.delegate = context.coordinator
        textView.accessibilityIdentifier = "NoteEditorTextView"
        return textView
    }

    func updateUIView(_ uiView: NoteEditorTextView, context: Context) {
        uiView.isEditable = isEditable
        uiView.isSelectable = true
        uiView.formattingBarPresentationMode = formattingBarPresentationMode
        let bridged = NoteEditorTextViewBridge.makeAttributedText(
            from: attributedContent,
            baseFontSize: baseFontSize
        )
        if uiView.attributedText != bridged {
            uiView.attributedText = bridged
        }
        if shouldFocus, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !shouldFocus, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedContent: $attributedContent, selection: $selection)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var attributedContent: Binding<AttributedString>
        private var selection: Binding<AttributedTextSelection>

        init(
            attributedContent: Binding<AttributedString>,
            selection: Binding<AttributedTextSelection>
        ) {
            self.attributedContent = attributedContent
            self.selection = selection
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let attributedText = textView.attributedText else { return }
            attributedContent.wrappedValue = AttributedString(attributedText)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            let attributedText = attributedContent.wrappedValue
            let lower = NoteEditorTextViewBridge.index(
                forUTF16Offset: selectedRange.location,
                in: attributedText
            )
            let upper = NoteEditorTextViewBridge.index(
                forUTF16Offset: selectedRange.location + selectedRange.length,
                in: attributedText
            )
            selection.wrappedValue = AttributedTextSelection(range: lower..<upper)
        }
    }
}

@available(iOS 26.0, *)
private enum NoteEditorTextViewBridge {
    static func makeAttributedText(
        from text: AttributedString,
        baseFontSize: CGFloat
    ) -> NSAttributedString {
        let constrained = NoteTextFormattingDefinition(baseFontSize: baseFontSize)
            .constrainedDocument(text)
        return (try? NSAttributedString(constrained, including: \.noteTextEditor))
            ?? NSAttributedString(constrained)
    }

    static func index(
        forUTF16Offset utf16Offset: Int,
        in text: AttributedString
    ) -> AttributedString.Index {
        let string = String(text.characters)
        let clampedOffset = max(0, min(utf16Offset, string.utf16.count))
        let stringIndex = String.Index(utf16Offset: clampedOffset, in: string)
        let characterDistance = string.distance(from: string.startIndex, to: stringIndex)
        return text.index(text.startIndex, offsetByCharacters: characterDistance)
    }
}

@available(iOS 26.0, *)
final class NoteEditorTextView: UITextView {
    var formattingBarPresentationMode: NoteFormattingBarPresentationMode = .accessoryBar
}
#endif
