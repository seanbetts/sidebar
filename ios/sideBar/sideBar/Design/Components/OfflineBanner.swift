import SwiftUI

struct OfflineBanner: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isPendingWritesPresented = false

    var body: some View {
        if shouldShow {
            Button {
                isPendingWritesPresented = true
            } label: {
                statusIcon
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                #if !os(macOS)
                .padding(.vertical, -4)
                #endif
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .sheet(isPresented: $isPendingWritesPresented) {
                NavigationStack {
                    PendingWritesView()
                }
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
}
