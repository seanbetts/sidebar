#if os(iOS)
import SwiftUI
import sideBarShared
import UIKit

// MARK: - ChatInputUIKit

struct ChatInputUIKitView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue
    private var sideButtonSize: CGFloat = HeaderActionControlMetrics.iconFrameHeight
    let isEnabled: Bool
    let isSendEnabled: Bool
    let isAttachEnabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSend: () -> Void
    let onAttach: () -> Void

    init(
        text: Binding<String>,
        measuredHeight: Binding<CGFloat>,
        isEnabled: Bool,
        isSendEnabled: Bool,
        isAttachEnabled: Bool,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        onSend: @escaping () -> Void,
        onAttach: @escaping () -> Void
    ) {
        self._text = text
        self._measuredHeight = measuredHeight
        self.isEnabled = isEnabled
        self.isSendEnabled = isSendEnabled
        self.isAttachEnabled = isAttachEnabled
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.onSend = onSend
        self.onAttach = onAttach
    }

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

        let placeholderLabel = makePlaceholderLabel(
            font: resolvedFont,
            adjustsForContentSizeCategory: usesSystemTextSize
        )
        let attachButton = makeAccessoryButton(systemName: "paperclip")
        attachButton.accessibilityLabel = "Attach file"
        attachButton.addTarget(context.coordinator, action: #selector(Coordinator.didTapAttach), for: .touchUpInside)

        let button = makeAccessoryButton(systemName: "arrow.up")
        button.layer.cornerRadius = sideButtonSize / 2
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
            attachButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: sideButtonSize),
            attachButton.heightAnchor.constraint(equalToConstant: sideButtonSize),
            button.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -sideButtonHorizontalInset),
            button.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
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

    private func makePlaceholderLabel(
        font: UIFont,
        adjustsForContentSizeCategory: Bool
    ) -> UILabel {
        let label = UILabel()
        label.text = "Ask Anything..."
        label.font = font
        label.adjustsFontForContentSizeCategory = adjustsForContentSizeCategory
        label.textColor = UIColor.secondaryLabel
        label.numberOfLines = 1
        return label
    }

    private func makeAccessoryButton(systemName: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(
                systemName: systemName,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: sideButtonSymbolSize,
                    weight: .semibold
                )
            ),
            for: .normal
        )
        button.clipsToBounds = true
        return button
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
        let shouldAllowEditing = ChatInputInteractivity.textViewIsEditable(
            isEnabled: isEnabled,
            isFirstResponder: textView.isFirstResponder
        )
        if textView.isEditable != shouldAllowEditing {
            textView.isEditable = shouldAllowEditing
        }
        let canSend = isSendEnabled && !text.trimmed.isEmpty
        button.isEnabled = canSend
        button.alpha = canSend ? 1.0 : 0.45
        let tintColor: UIColor = .label
        button.backgroundColor = .clear
        button.tintColor = canSend ? tintColor : UIColor.secondaryLabel
        attachButton.isEnabled = isAttachEnabled
        attachButton.alpha = isAttachEnabled ? 1.0 : 0.45
        attachButton.tintColor = isAttachEnabled ? UIColor.secondaryLabel : UIColor.tertiaryLabel
        placeholderLabel.isHidden = !text.trimmed.isEmpty
        context.coordinator.applySizing(for: textView, deferStateMutation: true)
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

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        private var measuredHeight: Binding<CGFloat>
        private var deferredHeightState = ChatInputDeferredHeightState()
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
            let stateMeasuredHeight = ChatInputSizing.stateMeasuredHeight(
                for: sizing.measuredHeight,
                minHeight: minHeight
            )
            if measuredHeight.wrappedValue != stateMeasuredHeight {
                if deferStateMutation {
                    guard deferredHeightState.shouldSchedule(
                        currentMeasuredHeight: measuredHeight.wrappedValue,
                        targetMeasuredHeight: stateMeasuredHeight
                    ) else {
                        return
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if self.measuredHeight.wrappedValue == stateMeasuredHeight {
                            self.deferredHeightState.didApply(measuredHeight: stateMeasuredHeight)
                            return
                        }
                        self.measuredHeight.wrappedValue = stateMeasuredHeight
                        self.deferredHeightState.didApply(measuredHeight: stateMeasuredHeight)
                    }
                } else {
                    measuredHeight.wrappedValue = stateMeasuredHeight
                    deferredHeightState.didApply(measuredHeight: stateMeasuredHeight)
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

    private var textInsetTop: CGFloat {
        AppFontStyle.scaledMetric(12, for: resolvedTextSizeOption)
    }

    private var textInsetBottom: CGFloat {
        AppFontStyle.scaledMetric(10, for: resolvedTextSizeOption)
    }

    private var textInsetLeading: CGFloat {
        AppFontStyle.scaledMetric(44, for: resolvedTextSizeOption)
    }

    private var textInsetTrailing: CGFloat {
        AppFontStyle.scaledMetric(48, for: resolvedTextSizeOption)
    }

    private var sideButtonSymbolSize: CGFloat {
        AppFontStyle.scaledMetric(DesignTokens.Icon.md, for: resolvedTextSizeOption)
    }

    private var sideButtonHorizontalInset: CGFloat {
        AppFontStyle.scaledMetric(10, for: resolvedTextSizeOption)
    }

    private var placeholderTopInset: CGFloat {
        AppFontStyle.scaledMetric(8, for: resolvedTextSizeOption)
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
