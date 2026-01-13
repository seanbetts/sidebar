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
            if isSecure {
                SecureField(title, text: $text)
                    .textContentType(textContentType)
                    .onSubmit { onSubmit?() }
            } else {
                TextField(title, text: $text)
                    .textContentType(textContentType)
                    .onSubmit { onSubmit?() }
            }

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
