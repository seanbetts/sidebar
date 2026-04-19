#if os(iOS)
import SwiftUI
import sideBarShared
import UIKit

// MARK: - ChatInputUIKit

struct ChatInputUIKitView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @Binding var isFocused: Bool
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
        isFocused: Binding<Bool>,
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
        self._isFocused = isFocused
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
        textView.isSelectable = true
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
        textView.accessibilityIdentifier = "chat-message-text-view"
        textView.onDidMoveToWindow = context.coordinator.handleTextViewDidMoveToWindow
        textView.refreshUITestAccessibilityValue()

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
        context.coordinator.isFocused = $isFocused
        context.coordinator.isInputEnabled = isEnabled
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
        context.coordinator.isFocused = $isFocused
        context.coordinator.isInputEnabled = isEnabled
        let resolvedFont = textFont()
        textView.font = resolvedFont
        textView.adjustsFontForContentSizeCategory = usesSystemTextSizeOption
        placeholderLabel.font = resolvedFont
        placeholderLabel.adjustsFontForContentSizeCategory = usesSystemTextSizeOption
        if textView.text != text {
            textView.text = text
        }
        if context.coordinator.syncCollapsedStateIfNeeded(for: textView, text: text) {
            context.coordinator.syncFocusIfNeeded(for: textView, isEnabled: isEnabled, isFocused: isFocused)
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
            (textView as? ChatInputTextView)?.refreshUITestAccessibilityValue()
            return
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
        context.coordinator.syncFocusIfNeeded(for: textView, isEnabled: isEnabled, isFocused: isFocused)
        context.coordinator.applySizing(for: textView, deferStateMutation: true)
        (textView as? ChatInputTextView)?.refreshUITestAccessibilityValue()
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
        var isFocused: Binding<Bool>?
        var isInputEnabled = true
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
            (textView as? ChatInputTextView)?.refreshUITestAccessibilityValue()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.isScrollEnabled else { return }
            textView.scrollRangeToVisible(textView.selectedRange)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = true
            (textView as? ChatInputTextView)?.refreshUITestAccessibilityValue()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = false
            (textView as? ChatInputTextView)?.refreshUITestAccessibilityValue()
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

        func syncCollapsedStateIfNeeded(for textView: UITextView, text: String) -> Bool {
            guard text.trimmed.isEmpty else { return false }
            deferredHeightState.cancelPending()
            if measuredHeight.wrappedValue != 0 {
                measuredHeight.wrappedValue = 0
            }
            if textView.isScrollEnabled {
                textView.isScrollEnabled = false
            }
            if textView.contentOffset != .zero {
                textView.setContentOffset(.zero, animated: false)
            }
            return true
        }

        func handleTextViewDidMoveToWindow(_ textView: ChatInputTextView) {
            textView.refreshUITestAccessibilityValue()
            scheduleAutofocusIfNeeded(for: textView)
        }

        func syncFocusIfNeeded(for textView: UITextView, isEnabled: Bool, isFocused: Bool) {
            guard isEnabled else {
                if let chatTextView = textView as? ChatInputTextView {
                    chatTextView.shouldAutofocus = false
                    chatTextView.hasScheduledAutofocus = false
                }
                if textView.isFirstResponder {
                    _ = textView.resignFirstResponder()
                }
                return
            }
            guard let chatTextView = textView as? ChatInputTextView else { return }
            chatTextView.shouldAutofocus = isEnabled && isFocused
            guard chatTextView.shouldAutofocus else {
                chatTextView.hasScheduledAutofocus = false
                return
            }
            scheduleAutofocusIfNeeded(for: chatTextView)
        }

        private func scheduleAutofocusIfNeeded(for textView: ChatInputTextView) {
            guard textView.shouldAutofocus else { return }
            guard textView.window != nil else { return }
            guard !textView.isFirstResponder else { return }
            guard !textView.hasScheduledAutofocus else { return }
            textView.hasScheduledAutofocus = true
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                defer { textView.hasScheduledAutofocus = false }
                guard textView.shouldAutofocus else { return }
                guard textView.window != nil else { return }
                guard !textView.isFirstResponder else { return }
                textView.window?.makeKey()
                let didBecomeFirstResponder = textView.becomeFirstResponder()
                textView.recordFocusAttempt(
                    source: "autofocus",
                    succeeded: didBecomeFirstResponder
                )
            }
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
            if deferStateMutation {
                guard deferredHeightState.shouldSchedule(
                    currentMeasuredHeight: measuredHeight.wrappedValue,
                    targetMeasuredHeight: stateMeasuredHeight
                ) else {
                    if textView.isScrollEnabled != sizing.isOverflowing {
                        textView.isScrollEnabled = sizing.isOverflowing
                    }
                    if sizing.isOverflowing {
                        textView.scrollRangeToVisible(textView.selectedRange)
                    }
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.deferredHeightState.shouldApplyScheduled(measuredHeight: stateMeasuredHeight) else {
                        return
                    }
                    if self.measuredHeight.wrappedValue == stateMeasuredHeight {
                        self.deferredHeightState.didApply(measuredHeight: stateMeasuredHeight)
                        return
                    }
                    self.measuredHeight.wrappedValue = stateMeasuredHeight
                    self.deferredHeightState.didApply(measuredHeight: stateMeasuredHeight)
                }
            } else if measuredHeight.wrappedValue != stateMeasuredHeight {
                measuredHeight.wrappedValue = stateMeasuredHeight
                deferredHeightState.didApply(measuredHeight: stateMeasuredHeight)
            }
            if textView.isScrollEnabled != sizing.isOverflowing {
                textView.isScrollEnabled = sizing.isOverflowing
            }
            if sizing.isOverflowing {
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }
    }

}

final class ChatInputTextView: UITextView {
    private static let uiTestDiagnosticsEnvironmentKey = "SIDEBAR_UI_TEST_USE_IN_MEMORY_AUTH"

    var onEnter: (() -> Void)?
    var onDidMoveToWindow: ((ChatInputTextView) -> Void)?
    var shouldAutofocus = false
    var hasScheduledAutofocus = false
    var lastFocusAttemptSource = "none"
    var lastFocusAttemptSucceeded: Bool?
    private var isInsertingShiftNewline = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshUITestAccessibilityValue()
        onDidMoveToWindow?(self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard isEditable, isUserInteractionEnabled, !isFirstResponder else { return }
        let didBecomeFirstResponder = becomeFirstResponder()
        recordFocusAttempt(
            source: "touchesEnded",
            succeeded: didBecomeFirstResponder
        )
    }

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

    func recordFocusAttempt(source: String, succeeded: Bool) {
        lastFocusAttemptSource = source
        lastFocusAttemptSucceeded = succeeded
        refreshUITestAccessibilityValue()
    }

    func refreshUITestAccessibilityValue() {
        guard Self.isUITestDiagnosticsEnabled else { return }
        let lastFocusAttemptSucceededValue: String
        if let lastFocusAttemptSucceeded {
            lastFocusAttemptSucceededValue = lastFocusAttemptSucceeded ? "1" : "0"
        } else {
            lastFocusAttemptSucceededValue = "nil"
        }
        accessibilityValue = [
            "editable=\(isEditable ? 1 : 0)",
            "selectable=\(isSelectable ? 1 : 0)",
            "interactive=\(isUserInteractionEnabled ? 1 : 0)",
            "window=\(window == nil ? 0 : 1)",
            "firstResponder=\(isFirstResponder ? 1 : 0)",
            "shouldAutofocus=\(shouldAutofocus ? 1 : 0)",
            "autofocusScheduled=\(hasScheduledAutofocus ? 1 : 0)",
            "lastFocusAttemptSource=\(lastFocusAttemptSource)",
            "lastFocusAttemptSucceeded=\(lastFocusAttemptSucceededValue)"
        ].joined(separator: " ")
    }

    private static var isUITestDiagnosticsEnabled: Bool {
        ProcessInfo.processInfo.environment[uiTestDiagnosticsEnvironmentKey] == "1"
    }
}
#endif
