import SwiftUI
import sideBarShared

enum LoginCredentialAutofillHints {
    static let email: PlatformTextContentType = .username
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

enum LoginFocusPolicy {
    static func shouldAutofocusEmail(isOnboardingPresented: Bool) -> Bool {
        !isOnboardingPresented
    }
}

enum LoginChrome {
    static let fieldKind: GlassChrome.Kind = .field
    static let noticeKind: GlassChrome.Kind = .card
}

enum LoginFieldChromeMetrics {
    private static let baseRowSpacing: CGFloat = 10
    private static let baseLeadingIconWidth: CGFloat = 18
    private static let baseFieldHorizontalPadding: CGFloat = DesignTokens.Spacing.sm
    private static let baseFieldVerticalPadding: CGFloat = DesignTokens.Spacing.xsPlus
    private static let baseTrailingControlSpacing: CGFloat = 8
    private static let baseTrailingSymbolPointSize: CGFloat = 18
    private static let baseStatusBadgeSize: CGFloat = 18
    private static let baseStatusBadgeSymbolSize: CGFloat = 10

    static var rowSpacing: CGFloat { AppFontStyle.scaledMetric(baseRowSpacing, for: .current) }
    static var leadingIconWidth: CGFloat { AppFontStyle.scaledMetric(baseLeadingIconWidth, for: .current) }
    static var fieldHorizontalPadding: CGFloat {
        AppFontStyle.scaledMetric(baseFieldHorizontalPadding, for: .current)
    }
    static var fieldVerticalPadding: CGFloat {
        AppFontStyle.scaledMetric(baseFieldVerticalPadding, for: .current)
    }
    static var trailingControlSpacing: CGFloat {
        AppFontStyle.scaledMetric(baseTrailingControlSpacing, for: .current)
    }
    static var trailingSymbolPointSize: CGFloat {
        AppFontStyle.scaledMetric(baseTrailingSymbolPointSize, for: .current)
    }
    static var statusBadgeSize: CGFloat {
        AppFontStyle.scaledMetric(baseStatusBadgeSize, for: .current)
    }
    static var statusBadgeSymbolSize: CGFloat {
        AppFontStyle.scaledMetric(baseStatusBadgeSymbolSize, for: .current)
    }
}

struct LoginPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(.subheading)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(minHeight: DesignTokens.Size.touchTarget)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous)
                    .fill(
                        backgroundColor.opacity(
                            fillOpacity(isPressed: configuration.isPressed)
                        )
                    )
            )
            .opacity(isEnabled ? 1 : 0.72)
            .animation(.easeOut(duration: DesignTokens.Animation.quick), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private func fillOpacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.5 }
        return isPressed ? 0.8 : 1
    }
}

enum LoginEmailPrefill {
    static func initialEmail(currentEmail: String, storedEmail: String) -> String {
        guard currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return currentEmail
        }
        return storedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
