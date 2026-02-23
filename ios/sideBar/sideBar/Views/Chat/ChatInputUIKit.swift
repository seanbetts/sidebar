#if os(iOS)
import SwiftUI
import sideBarShared
import UIKit

// MARK: - ChatInputUIKit

struct ChatInputUIKitView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue
    @ScaledMetric(relativeTo: .body) private var textInsetTop: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var textInsetBottom: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var textInsetLeading: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var textInsetTrailing: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var sideButtonSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var sideButtonHorizontalInset: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var sideButtonBottomInset: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var placeholderTopInset: CGFloat = 8
    let resetToken: UUID
    let isEnabled: Bool
    let isSendEnabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSend: () -> Void
    let onAttach: () -> Void

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        let resolvedFont = textFont()
        let usesSystemTextSize = usesSystemTextSizeOption

        let textView = ChatInputTextView()
        textView.font = resolvedFont
        textView.adjustsFontForContentSizeCategory = usesSystemTextSize
        textView.backgroundColor = .clear
        textView.textColor = UIColor.label
        textView.textContainerInset = UIEdgeInsets(
            top: textInsetTop,
            left: textInsetLeading,
            bottom: textInsetBottom,
            right: textInsetTrailing
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.returnKeyType = .send
        textView.delegate = context.coordinator
        textView.onEnter = onSend
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.accessibilityLabel = "Message"

        let placeholderLabel = UILabel()
        placeholderLabel.text = "Ask Anything..."
        placeholderLabel.font = resolvedFont
        placeholderLabel.adjustsFontForContentSizeCategory = usesSystemTextSize
        placeholderLabel.textColor = UIColor.secondaryLabel
        placeholderLabel.numberOfLines = 1

        let attachButton = UIButton(type: .system)
        attachButton.setImage(UIImage(systemName: "paperclip.circle.fill"), for: .normal)
        attachButton.clipsToBounds = true
        attachButton.accessibilityLabel = "Attach file"
        attachButton.addTarget(context.coordinator, action: #selector(Coordinator.didTapAttach), for: .touchUpInside)

        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.layer.cornerRadius = sideButtonSize / 2
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
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textInsetLeading),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: textView.trailingAnchor,
                constant: -textInsetTrailing
            ),
            placeholderLabel.topAnchor.constraint(greaterThanOrEqualTo: textView.topAnchor, constant: placeholderTopInset),
            attachButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: sideButtonHorizontalInset),
            attachButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -sideButtonBottomInset),
            attachButton.widthAnchor.constraint(equalToConstant: sideButtonSize),
            attachButton.heightAnchor.constraint(equalToConstant: sideButtonSize),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -sideButtonHorizontalInset),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -sideButtonBottomInset),
            button.widthAnchor.constraint(equalToConstant: sideButtonSize),
            button.heightAnchor.constraint(equalToConstant: sideButtonSize)
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
        let resolvedFont = textFont()
        textView.font = resolvedFont
        textView.adjustsFontForContentSizeCategory = usesSystemTextSizeOption
        placeholderLabel.font = resolvedFont
        placeholderLabel.adjustsFontForContentSizeCategory = usesSystemTextSizeOption
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
        attachButton.isEnabled = isEnabled
        attachButton.alpha = isEnabled ? 1.0 : 0.45
        attachButton.tintColor = isEnabled ? UIColor.secondaryLabel : UIColor.tertiaryLabel
        placeholderLabel.isHidden = !text.trimmed.isEmpty
        context.coordinator.applyResetIfNeeded(token: resetToken, textView: textView)
        context.coordinator.applySizing(for: textView, deferStateMutation: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            initialResetToken: resetToken,
            minHeight: minHeight,
            maxHeight: maxHeight,
            onSend: onSend,
            onAttach: onAttach
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        private var measuredHeight: Binding<CGFloat>
        private var resetToken: UUID
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
            initialResetToken: UUID,
            minHeight: CGFloat,
            maxHeight: CGFloat,
            onSend: @escaping () -> Void,
            onAttach: @escaping () -> Void
        ) {
            self.text = text
            self.measuredHeight = measuredHeight
            resetToken = initialResetToken
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.onSend = onSend
            self.onAttach = onAttach
        }

        func applyResetIfNeeded(token: UUID, textView: UITextView) {
            guard resetToken != token else { return }
            resetToken = token
            textView.isScrollEnabled = false
            textView.setContentOffset(.zero, animated: false)
            let end = textView.endOfDocument
            textView.selectedTextRange = textView.textRange(from: end, to: end)
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            placeholderLabel?.isHidden = !textView.text.trimmed.isEmpty
            applySizing(for: textView, deferStateMutation: false)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.isScrollEnabled else { return }
            textView.scrollRangeToVisible(textView.selectedRange)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text == "\n" else { return true }
            if let chatTextView = textView as? ChatInputTextView, chatTextView.consumeShiftNewlineInsertionFlag() {
                return true
            }
            if chatInputReturnIntent(shiftPressed: false) == .send {
                onSend()
                return false
            }
            return true
        }

        @objc func didTapSend() {
            onSend()
        }

        @objc func didTapAttach() {
            onAttach()
        }

        func applySizing(for textView: UITextView, deferStateMutation: Bool) {
            let fittingWidth = max(textView.bounds.width, 1)
            let size = textView.sizeThatFits(CGSize(width: fittingWidth, height: .greatestFiniteMagnitude))
            let sizing = ChatInputSizing.resolve(
                contentHeight: size.height,
                minHeight: minHeight,
                maxHeight: maxHeight
            )
            if measuredHeight.wrappedValue != sizing.measuredHeight {
                if deferStateMutation {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        guard self.measuredHeight.wrappedValue != sizing.measuredHeight else { return }
                        self.measuredHeight.wrappedValue = sizing.measuredHeight
                    }
                } else {
                    measuredHeight.wrappedValue = sizing.measuredHeight
                }
            }
            if textView.isScrollEnabled != sizing.isOverflowing {
                textView.isScrollEnabled = sizing.isOverflowing
            }
            if sizing.isOverflowing {
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }
    }

    private var resolvedTextSizeOption: AppTextSizeOption {
        AppTextSizeOption.resolved(from: appTextSizeRaw)
    }

    private var usesSystemTextSizeOption: Bool {
        resolvedTextSizeOption == .system
    }

    private func textFont() -> UIFont {
        let option = resolvedTextSizeOption
        switch option {
        case .system:
            return UIFont.preferredFont(forTextStyle: .body)
        case .small, .medium, .large:
            return UIFont.systemFont(ofSize: AppFontStyle.body.pointSize(for: option))
        }
    }
}

final class ChatInputTextView: UITextView {
    var onEnter: (() -> Void)?
    private var isInsertingShiftNewline = false

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                input: "\r",
                modifierFlags: [],
                action: #selector(handleEnter)
            ),
            UIKeyCommand(
                input: "\r",
                modifierFlags: .shift,
                action: #selector(handleShiftEnter)
            )
        ]
    }

    @objc private func handleEnter() {
        if chatInputReturnIntent(shiftPressed: false) == .send {
            onEnter?()
        }
    }

    @objc private func handleShiftEnter() {
        if chatInputReturnIntent(shiftPressed: true) == .insertNewline {
            isInsertingShiftNewline = true
            insertText("\n")
        }
    }

    func consumeShiftNewlineInsertionFlag() -> Bool {
        let shouldInsertNewline = isInsertingShiftNewline
        isInsertingShiftNewline = false
        return shouldInsertNewline
    }
}
#endif
