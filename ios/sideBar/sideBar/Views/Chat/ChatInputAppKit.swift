#if os(macOS)
import AppKit
import SwiftUI

struct ChatInputAppKitView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let isEnabled: Bool
    let isSendEnabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    private let controlBarHeight: CGFloat = 44
    let onSend: () -> Void
    let onAttach: () -> Void

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()

        let textView = NSTextView()
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = context.coordinator
        textView.textColor = .labelColor
        textView.string = text
        textView.setAccessibilityLabel("Message")

        let controlBar = NSView()
        controlBar.wantsLayer = true
        controlBar.layer?.backgroundColor = NSColor.clear.cgColor

        let placeholderLabel = NSTextField(labelWithString: "Ask Anything...")
        placeholderLabel.font = textView.font
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
            NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
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
            NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        )
        button.wantsLayer = true
        button.layer?.cornerRadius = 22
        button.target = context.coordinator
        button.action = #selector(Coordinator.didTapSend)
        button.setAccessibilityLabel("Send message")

        containerView.addSubview(textView)
        containerView.addSubview(placeholderLabel)
        containerView.addSubview(controlBar)
        controlBar.addSubview(attachButton)
        controlBar.addSubview(button)
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: controlBar.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -16),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.height + 2),
            controlBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            controlBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: controlBarHeight),
            attachButton.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor, constant: 6),
            attachButton.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 48),
            attachButton.heightAnchor.constraint(equalToConstant: 48),
            button.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -6),
            button.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 48),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])

        context.coordinator.textView = textView
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
        attachButton.contentTintColor = isEnabled ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
        placeholderLabel.isHidden = !text.trimmed.isEmpty
        recalculateHeight(for: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            minHeight: minHeight,
            maxHeight: maxHeight,
            controlBarHeight: controlBarHeight,
            onSend: onSend,
            onAttach: onAttach
        )
    }

    private func recalculateHeight(for textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let contentHeight = usedRect.height + textView.textContainerInset.height * 2
        let height = min(maxHeight, max(minHeight, contentHeight + controlBarHeight))
        if measuredHeight != height {
            DispatchQueue.main.async {
                measuredHeight = height
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private var measuredHeight: Binding<CGFloat>
        private let minHeight: CGFloat
        private let maxHeight: CGFloat
        private let controlBarHeight: CGFloat
        private let onSend: () -> Void
        private let onAttach: () -> Void
        weak var textView: NSTextView?
        weak var sendButton: NSButton?
        weak var attachButton: NSButton?
        weak var placeholderLabel: NSTextField?

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            minHeight: CGFloat,
            maxHeight: CGFloat,
            controlBarHeight: CGFloat,
            onSend: @escaping () -> Void,
            onAttach: @escaping () -> Void
        ) {
            self.text = text
            self.measuredHeight = measuredHeight
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.controlBarHeight = controlBarHeight
            self.onSend = onSend
            self.onAttach = onAttach
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            placeholderLabel?.isHidden = !textView.string.trimmed.isEmpty
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
                return
            }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let contentHeight = usedRect.height + textView.textContainerInset.height * 2
            let height = min(maxHeight, max(minHeight, contentHeight + controlBarHeight))
            if measuredHeight.wrappedValue != height {
                measuredHeight.wrappedValue = height
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            if NSEvent.modifierFlags.contains(.shift) {
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
    }
}
#endif
