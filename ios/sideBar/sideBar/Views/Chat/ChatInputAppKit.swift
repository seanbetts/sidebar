#if os(macOS)
import AppKit
import sideBarShared
import SwiftUI

// MARK: - ChatInputAppKit

struct ChatInputAppKitView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue
    @ScaledMetric(relativeTo: .body) private var controlBarHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var textHorizontalInset: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var textVerticalInset: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var sideButtonInset: CGFloat = 6
    @ScaledMetric(relativeTo: .body) private var sideButtonSize: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var sideButtonSymbolSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var cornerRadiusAdjustment: CGFloat = 2
    let resetToken: UUID
    let isEnabled: Bool
    let isSendEnabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSend: () -> Void
    let onAttach: () -> Void

    // swiftlint:disable:next function_body_length
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        let resolvedFont = textFont()

        let textView = NSTextView()
        textView.font = resolvedFont
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: textHorizontalInset, height: textVerticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = context.coordinator
        textView.textColor = .labelColor
        textView.string = text
        textView.setAccessibilityLabel("Message")

        let textScrollView = NSScrollView()
        textScrollView.drawsBackground = false
        textScrollView.borderType = .noBorder
        textScrollView.hasHorizontalScroller = false
        textScrollView.hasVerticalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.scrollerStyle = .overlay
        textScrollView.documentView = textView

        let controlBar = NSView()
        controlBar.wantsLayer = true
        controlBar.layer?.backgroundColor = NSColor.clear.cgColor

        let placeholderLabel = NSTextField(labelWithString: "Ask Anything...")
        placeholderLabel.font = resolvedFont
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.isBordered = false
        placeholderLabel.isEditable = false
        placeholderLabel.lineBreakMode = .byTruncatingTail

        let attachButton = NSButton()
        attachButton.bezelStyle = .regularSquare
        attachButton.isBordered = false
        attachButton.image = NSImage(
            systemSymbolName: "paperclip.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: sideButtonSymbolSize, weight: .semibold)
        )
        attachButton.setAccessibilityLabel("Attach file")
        attachButton.target = context.coordinator
        attachButton.action = #selector(Coordinator.didTapAttach)

        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: "arrow.up.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: sideButtonSymbolSize, weight: .semibold)
        )
        button.wantsLayer = true
        button.layer?.cornerRadius = max(0, (sideButtonSize / 2) - cornerRadiusAdjustment)
        button.target = context.coordinator
        button.action = #selector(Coordinator.didTapSend)
        button.setAccessibilityLabel("Send message")

        containerView.addSubview(textScrollView)
        containerView.addSubview(placeholderLabel)
        containerView.addSubview(controlBar)
        controlBar.addSubview(attachButton)
        controlBar.addSubview(button)
        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textScrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textScrollView.bottomAnchor.constraint(equalTo: controlBar.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textScrollView.leadingAnchor, constant: textHorizontalInset),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textScrollView.trailingAnchor, constant: -textHorizontalInset),
            placeholderLabel.topAnchor.constraint(equalTo: textScrollView.topAnchor, constant: textView.textContainerInset.height + 2),
            controlBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            controlBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: controlBarHeight),
            attachButton.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor, constant: sideButtonInset),
            attachButton.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: sideButtonSize),
            attachButton.heightAnchor.constraint(equalToConstant: sideButtonSize),
            button.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -sideButtonInset),
            button.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: sideButtonSize),
            button.heightAnchor.constraint(equalToConstant: sideButtonSize)
        ])

        context.coordinator.textView = textView
        context.coordinator.textScrollView = textScrollView
        context.coordinator.sendButton = button
        context.coordinator.attachButton = attachButton
        context.coordinator.placeholderLabel = placeholderLabel
        placeholderLabel.isHidden = !text.trimmed.isEmpty
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = context.coordinator.textView,
              let button = context.coordinator.sendButton,
              let attachButton = context.coordinator.attachButton,
              let placeholderLabel = context.coordinator.placeholderLabel else {
            return
        }
        let resolvedFont = textFont()
        textView.font = resolvedFont
        placeholderLabel.font = resolvedFont
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        let canSend = isSendEnabled && !text.trimmed.isEmpty
        button.isEnabled = canSend
        button.alphaValue = canSend ? 1.0 : 0.45
        let tintColor: NSColor = .labelColor
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.contentTintColor = canSend ? tintColor : NSColor.secondaryLabelColor
        attachButton.isEnabled = isEnabled
        attachButton.alphaValue = isEnabled ? 1.0 : 0.45
        attachButton.contentTintColor = isEnabled ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
        placeholderLabel.isHidden = !text.trimmed.isEmpty
        if !isEnabled, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
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
            controlBarHeight: controlBarHeight,
            onSend: onSend,
            onAttach: onAttach
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private var measuredHeight: Binding<CGFloat>
        private var resetToken: UUID
        private var deferredHeightState = ChatInputDeferredHeightState()
        private let minHeight: CGFloat
        private let maxHeight: CGFloat
        private let controlBarHeight: CGFloat
        private let onSend: () -> Void
        private let onAttach: () -> Void
        weak var textView: NSTextView?
        weak var textScrollView: NSScrollView?
        weak var sendButton: NSButton?
        weak var attachButton: NSButton?
        weak var placeholderLabel: NSTextField?

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            initialResetToken: UUID,
            minHeight: CGFloat,
            maxHeight: CGFloat,
            controlBarHeight: CGFloat,
            onSend: @escaping () -> Void,
            onAttach: @escaping () -> Void
        ) {
            self.text = text
            self.measuredHeight = measuredHeight
            resetToken = initialResetToken
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.controlBarHeight = controlBarHeight
            self.onSend = onSend
            self.onAttach = onAttach
        }

        func applyResetIfNeeded(token: UUID, textView: NSTextView) {
            guard resetToken != token else { return }
            resetToken = token
            if let scrollView = textView.enclosingScrollView ?? textScrollView {
                scrollView.hasVerticalScroller = false
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            let endLocation = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            placeholderLabel?.isHidden = !textView.string.trimmed.isEmpty
            applySizing(for: textView, deferStateMutation: false)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard (textView.enclosingScrollView ?? textScrollView)?.hasVerticalScroller == true else { return }
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            let shiftPressed = (textView.window?.currentEvent?.modifierFlags.contains(.shift) ?? false)
            if chatInputReturnIntent(shiftPressed: shiftPressed) == .insertNewline {
                return false
            }
            onSend()
            return true
        }

        @objc func didTapSend() {
            onSend()
        }

        @objc func didTapAttach() {
            onAttach()
        }

        func applySizing(for textView: NSTextView, deferStateMutation: Bool) {
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
                return
            }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let contentHeight = usedRect.height + textView.textContainerInset.height * 2
            let sizing = ChatInputSizing.resolve(
                contentHeight: contentHeight + controlBarHeight,
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
            if let scrollView = textView.enclosingScrollView ?? textScrollView,
               scrollView.hasVerticalScroller != sizing.isOverflowing {
                scrollView.hasVerticalScroller = sizing.isOverflowing
            }
            if sizing.isOverflowing {
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
    }

    private var resolvedTextSizeOption: AppTextSizeOption {
        AppTextSizeOption.resolved(from: appTextSizeRaw)
    }

    private func textFont() -> NSFont {
        let option = resolvedTextSizeOption
        switch option {
        case .system:
            return NSFont.preferredFont(forTextStyle: .body)
        case .small, .medium, .large:
            return NSFont.systemFont(ofSize: AppFontStyle.body.pointSize(for: option))
        }
    }
}
#endif
