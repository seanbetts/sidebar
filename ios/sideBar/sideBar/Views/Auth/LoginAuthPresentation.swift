import SwiftUI

enum LoginCredentialAutofillHints {
    static let email: PlatformTextContentType = .emailAddress
    static let password: PlatformTextContentType = .password

    static var emailIdentifier: String {
        #if canImport(UIKit) || canImport(AppKit)
        email.rawValue
        #else
        email
        #endif
    }

    static var passwordIdentifier: String {
        #if canImport(UIKit) || canImport(AppKit)
        password.rawValue
        #else
        password
        #endif
    }
}

struct LoginPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(.subheadlineSemibold)
            .foregroundStyle(Color.white)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(minHeight: DesignTokens.Size.touchTarget)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous)
                    .fill(
                        DesignTokens.Colors.actionPrimary.opacity(
                            fillOpacity(isPressed: configuration.isPressed)
                        )
                    )
            )
            .opacity(isEnabled ? 1 : 0.72)
            .animation(.easeOut(duration: DesignTokens.Animation.quick), value: configuration.isPressed)
    }

    private func fillOpacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.5 }
        return isPressed ? 0.8 : 1
    }
}
