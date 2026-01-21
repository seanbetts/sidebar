import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias PlatformTextContentType = UITextContentType
#elseif canImport(AppKit)
import AppKit
public typealias PlatformTextContentType = NSTextContentType
#else
public typealias PlatformTextContentType = String
#endif

public struct SecureFieldWithToggle<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    var textContentType: PlatformTextContentType?
    var onSubmit: (() -> Void)?

    @State private var isSecure = true

    public init(
        title: String,
        text: Binding<String>,
        focus: FocusState<Field?>.Binding,
        field: Field,
        textContentType: PlatformTextContentType? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self._text = text
        self.focus = focus
        self.field = field
        self.textContentType = textContentType
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 8) {
            #if canImport(UIKit)
            SecureTextFieldRepresentable(
                title: title,
                text: $text,
                isSecure: $isSecure,
                isFocused: focusBinding,
                textContentType: textContentType,
                onSubmit: onSubmit
            )
            #else
            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .textContentType(textContentType)
            .autocorrectionDisabled()
            #if canImport(UIKit)
            .textInputAutocapitalization(.never)
            #endif
            .focused(focus, equals: field)
            .onSubmit { onSubmit?() }
            #endif

            Button {
                isSecure.toggle()
            } label: {
                Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSecure ? "Show password" : "Hide password")
        }
    }

    private var focusBinding: Binding<Bool> {
        Binding(
            get: { focus.wrappedValue == field },
            set: { isFocused in
                focus.wrappedValue = isFocused ? field : nil
            }
        )
    }
}

#if canImport(UIKit)
private struct SecureTextFieldRepresentable: UIViewRepresentable {
    let title: String
    @Binding var text: String
    @Binding var isSecure: Bool
    @Binding var isFocused: Bool
    var textContentType: PlatformTextContentType?
    var onSubmit: (() -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = title
        textField.textContentType = textContentType
        textField.isSecureTextEntry = isSecure
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.returnKeyType = .go
        textField.enablesReturnKeyAutomatically = true
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange), for: .editingChanged)
        textField.delegate = context.coordinator
        context.coordinator.textField = textField
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Update text only if it differs (avoid cursor jumps)
        if uiView.text != text {
            uiView.text = text
        }

        // Handle secure entry toggle without resigning first responder
        if uiView.isSecureTextEntry != isSecure {
            // Store current selection
            let selectedRange = uiView.selectedTextRange
            let wasFirstResponder = uiView.isFirstResponder

            uiView.isSecureTextEntry = isSecure

            // SecureField requires re-setting text after mode change
            if uiView.text != text {
                uiView.text = text
            }

            // Restore selection if possible
            if wasFirstResponder, let range = selectedRange {
                uiView.selectedTextRange = range
            }
        }

        if uiView.textContentType != textContentType {
            uiView.textContentType = textContentType
        }

        // Handle focus changes - batch on next runloop to avoid conflicts
        let shouldBeFocused = isFocused
        let isCurrentlyFocused = uiView.isFirstResponder
        if shouldBeFocused != isCurrentlyFocused {
            context.coordinator.pendingFocusChange = shouldBeFocused
            context.coordinator.scheduleFocusUpdate()
        }

        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let text: Binding<String>
        private let isFocused: Binding<Bool>
        var onSubmit: (() -> Void)?
        weak var textField: UITextField?
        var pendingFocusChange: Bool?
        private var focusWorkItem: DispatchWorkItem?

        init(text: Binding<String>, isFocused: Binding<Bool>, onSubmit: (() -> Void)?) {
            self.text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
        }

        func scheduleFocusUpdate() {
            focusWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let textField = self.textField, let shouldFocus = self.pendingFocusChange else { return }
                self.pendingFocusChange = nil
                if shouldFocus && !textField.isFirstResponder {
                    textField.becomeFirstResponder()
                } else if !shouldFocus && textField.isFirstResponder {
                    textField.resignFirstResponder()
                }
            }
            focusWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        @objc func textDidChange(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            guard !isFocused.wrappedValue else { return }
            isFocused.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard isFocused.wrappedValue else { return }
            isFocused.wrappedValue = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit?()
            return true
        }
    }
}
#endif
