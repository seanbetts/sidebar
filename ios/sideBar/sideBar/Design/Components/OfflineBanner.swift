import SwiftUI

struct OfflineBanner: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isStatusAlertPresented = false

    var body: some View {
        if shouldShow {
            Button {
                isStatusAlertPresented = true
            } label: {
                statusIcon
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                #if !os(macOS)
                .padding(.vertical, -4)
                #endif
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Shows connection status details")
            .alert(statusAlertTitle, isPresented: $isStatusAlertPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(statusAlertMessage)
            }
        }
    }

    private var shouldShow: Bool {
        environment.isOffline || !environment.isServerReachable
    }

    private var accessibilityLabel: String {
        if environment.isOffline {
            return "Offline"
        }
        return "Server unreachable"
    }

    private var backgroundColor: Color {
        if environment.isOffline {
            return .red
        }
        return .orange
    }

    private var statusIcon: some View {
        if environment.isOffline {
            return Image(systemName: "wifi.slash")
        }
        return Image(systemName: "wifi.exclamationmark")
    }

    private var statusAlertTitle: String {
        if environment.isOffline {
            return "You are offline"
        }
        return "Server unreachable"
    }

    private var statusAlertMessage: String {
        if environment.isOffline {
            return "Your device does not currently have an internet connection. Reconnect to continue syncing."
        }
        return "Your internet connection is working, but the server can't be reached right now. Check server status and try again."
    }
}
