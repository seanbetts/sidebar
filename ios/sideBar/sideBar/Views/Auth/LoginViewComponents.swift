import SwiftUI
import sideBarShared

struct LoginPasswordResetNoticeView: View {
    let message: String
    let detail: String?

    var body: some View {
        HStack {
            VStack(alignment: .center, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.actionPrimary)
                Text(message)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .appFont(.body)
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .appFont(.caption)
                }
            }
            .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.Spacing.sm)
        .glassChrome(LoginChrome.noticeKind)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("Authentication notice")
        .accessibilityValue(message)
    }
}

struct LoginOfflineNoticeView: View {
    var body: some View {
        HStack {
            VStack(alignment: .center, spacing: 6) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(DesignTokens.Colors.error)
                Text("You're offline.")
                    .foregroundStyle(DesignTokens.Colors.error)
                    .appFont(.body)
                Text("Sign in requires a connection.")
                    .foregroundStyle(.secondary)
                    .appFont(.caption)
            }
            .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.Spacing.sm)
        .glassChrome(LoginChrome.noticeKind)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("Offline")
        .accessibilityValue("Sign in requires a connection.")
    }
}

struct LoginOfflineUnlockView: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("You're offline.")
                .appFont(.body)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text("Continue using your cached session.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Button(action: action) {
                if isLoading {
                    LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(title)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DesignTokens.Colors.actionPrimary)
            .disabled(isLoading)
        }
        .padding(DesignTokens.Spacing.sm)
        .glassChrome(LoginChrome.noticeKind)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct LoginPasswordResetActionRow: View {
    let isRequesting: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isRequesting ? "Sending…" : "Forgot password?")
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appFont(.caption)
        .foregroundStyle(color)
        .disabled(isRequesting)
        .frame(maxWidth: .infinity)
        .accessibilitySortPriority(1.5)
    }
}

struct LoginPrimaryActionLabel: View {
    let isLoading: Bool

    var body: some View {
        Group {
            if isLoading {
                LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Sign in")
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct LoginManualSignUpPrompt: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xsPlus) {
            Text("Need an account?")
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Button(action: action) {
                Text("Create one")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .appFont(.caption)
            .foregroundStyle(DesignTokens.Colors.actionPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}
