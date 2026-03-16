#if os(iOS)
import SwiftUI
import UIKit

struct SettingsIOSPlainTextEditor: UIViewRepresentable {
    @Binding var text: String
    let minHeight: CGFloat

    init(text: Binding<String>, minHeight: CGFloat = 120) {
        _text = text
        self.minHeight = minHeight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = Self.makeConfiguredTextView(
            text: text,
            delegate: context.coordinator
        )
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    static func makeConfiguredTextView(
        text: String,
        delegate: UITextViewDelegate?
    ) -> UITextView {
        let textView = UITextView()
        textView.text = text
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = delegate
        return textView
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        uiView.delegate = nil
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        weak var textView: UITextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
#endif
