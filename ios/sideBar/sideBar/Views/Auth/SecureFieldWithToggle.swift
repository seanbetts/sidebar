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

public struct SecureFieldWithToggle: View {
    let title: String
    @Binding var text: String
    var textContentType: PlatformTextContentType?
    var onSubmit: (() -> Void)?

    @State private var isSecure = true

    public init(
        title: String,
        text: Binding<String>,
        textContentType: PlatformTextContentType? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self._text = text
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
                textContentType: textContentType,
                onSubmit: onSubmit
            )
            #else
            if isSecure {
                SecureField(title, text: $text)
                    .textContentType(textContentType)
                    .autocorrectionDisabled()
            } else {
                TextField(title, text: $text)
                    .textContentType(textContentType)
                    .autocorrectionDisabled()
            }
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
}

#if canImport(UIKit)
private struct SecureTextFieldRepresentable: UIViewRepresentable {
    let title: String
    @Binding var text: String
    @Binding var isSecure: Bool
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
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange), for: .editingChanged)
        textField.delegate = context.coordinator
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.isSecureTextEntry != isSecure {
            let wasFirstResponder = uiView.isFirstResponder
            uiView.isSecureTextEntry = isSecure
            if wasFirstResponder {
                uiView.becomeFirstResponder()
            }
        }
        if uiView.textContentType != textContentType {
            uiView.textContentType = textContentType
        }
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let text: Binding<String>
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            self.text = text
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit?()
            return true
        }
    }
}
#endif
