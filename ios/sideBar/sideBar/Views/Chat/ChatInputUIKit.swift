#if os(iOS)
import SwiftUI
import UIKit

struct ChatInputUIKitView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let isEnabled: Bool
    let isSendEnabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSend: () -> Void
    let onAttach: () -> Void

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear

        let textView = ChatInputTextView()
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textColor = UIColor.label
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 44, bottom: 4, right: 48)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = context.coordinator
        textView.onShiftEnter = {
            textView.allowNewlineOnce = true
            textView.insertText("\n")
        }
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.accessibilityLabel = "Message"

        let placeholderLabel = UILabel()
        placeholderLabel.text = "Ask Anything..."
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = UIColor.secondaryLabel
        placeholderLabel.numberOfLines = 1

        let attachButton = UIButton(type: .system)
        attachButton.setImage(UIImage(systemName: "paperclip.circle.fill"), for: .normal)
        attachButton.clipsToBounds = true
        attachButton.accessibilityLabel = "Attach file"
        attachButton.addTarget(context.coordinator, action: #selector(Coordinator.didTapAttach), for: .touchUpInside)

        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.layer.cornerRadius = 14
        button.clipsToBounds = true
        button.addTarget(context.coordinator, action: #selector(Coordinator.didTapSend), for: .touchUpInside)
        button.accessibilityLabel = "Send message"

        containerView.addSubview(textView)
        containerView.addSubview(placeholderLabel)
        containerView.addSubview(attachButton)
        containerView.addSubview(button)

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false

        let placeholderCenter = placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor)
        placeholderCenter.priority = .defaultHigh

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 44),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -48),
            placeholderLabel.topAnchor.constraint(greaterThanOrEqualTo: textView.topAnchor, constant: 8),
            attachButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            attachButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            attachButton.widthAnchor.constraint(equalToConstant: 28),
            attachButton.heightAnchor.constraint(equalToConstant: 28),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        placeholderCenter.isActive = true

        context.coordinator.textView = textView
        context.coordinator.sendButton = button
        context.coordinator.attachButton = attachButton
        context.coordinator.placeholderLabel = placeholderLabel
        placeholderLabel.isHidden = !text.trimmed.isEmpty
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let textView = context.coordinator.textView,
              let button = context.coordinator.sendButton,
              let attachButton = context.coordinator.attachButton,
              let placeholderLabel = context.coordinator.placeholderLabel else {
            return
        }
        if textView.text != text {
            textView.text = text
        }
        textView.isEditable = isEnabled
        let canSend = isSendEnabled && !text.trimmed.isEmpty
        button.isEnabled = canSend
        button.alpha = canSend ? 1.0 : 0.45
        let tintColor: UIColor = .label
        button.backgroundColor = .clear
        button.tintColor = canSend ? tintColor : UIColor.secondaryLabel
        attachButton.tintColor = isEnabled ? UIColor.secondaryLabel : UIColor.tertiaryLabel
        placeholderLabel.isHidden = !text.trimmed.isEmpty
        recalculateHeight(for: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            minHeight: minHeight,
            maxHeight: maxHeight,
            onSend: onSend,
            onAttach: onAttach
        )
    }

    private func recalculateHeight(for textView: UITextView) {
        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let height = min(maxHeight, max(minHeight, size.height))
        if measuredHeight != height {
            DispatchQueue.main.async {
                measuredHeight = height
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        private var measuredHeight: Binding<CGFloat>
        private let minHeight: CGFloat
        private let maxHeight: CGFloat
        private let onSend: () -> Void
        private let onAttach: () -> Void
        weak var textView: UITextView?
        weak var sendButton: UIButton?
        weak var attachButton: UIButton?
        weak var placeholderLabel: UILabel?

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            minHeight: CGFloat,
            maxHeight: CGFloat,
            onSend: @escaping () -> Void,
            onAttach: @escaping () -> Void
        ) {
            self.text = text
            self.measuredHeight = measuredHeight
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.onSend = onSend
            self.onAttach = onAttach
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            placeholderLabel?.isHidden = !textView.text.trimmed.isEmpty
            let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
            let height = min(maxHeight, max(minHeight, size.height))
            if measuredHeight.wrappedValue != height {
                measuredHeight.wrappedValue = height
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text == "\n" else {
                return true
            }
            if let chatTextView = textView as? ChatInputTextView, chatTextView.allowNewlineOnce {
                chatTextView.allowNewlineOnce = false
                return true
            }
            onSend()
            return false
        }

        @objc func didTapSend() {
            onSend()
        }

        @objc func didTapAttach() {
            onAttach()
        }
    }
}

final class ChatInputTextView: UITextView {
    var allowNewlineOnce = false
    var onShiftEnter: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                input: "\r",
                modifierFlags: .shift,
                action: #selector(handleShiftEnter)
            )
        ]
    }

    @objc private func handleShiftEnter() {
        onShiftEnter?()
        allowNewlineOnce = false
    }
}
#endif
