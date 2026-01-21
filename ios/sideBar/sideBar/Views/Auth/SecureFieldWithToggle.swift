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
    var submitLabel: SubmitLabel
    var onSubmit: (() -> Void)?

    @State private var isSecure = true

    public init(
        title: String,
        text: Binding<String>,
        focus: FocusState<Field?>.Binding,
        field: Field,
        textContentType: PlatformTextContentType? = nil,
        submitLabel: SubmitLabel = .return,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self._text = text
        self.focus = focus
        self.field = field
        self.textContentType = textContentType
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 8) {
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
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }

            Button {
                // Preserve focus when toggling
                let wasFocused = focus.wrappedValue == field
                isSecure.toggle()
                if wasFocused {
                    // Re-focus after toggle on next runloop
                    DispatchQueue.main.async {
                        focus.wrappedValue = field
                    }
                }
            } label: {
                Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSecure ? "Show password" : "Hide password")
        }
    }
}
