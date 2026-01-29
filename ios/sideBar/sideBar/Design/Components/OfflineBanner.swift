import SwiftUI

struct OfflineBanner: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if shouldShow {
            HStack(spacing: 8) {
                statusIcon
                Text(statusText)
                    .font(DesignTokens.Typography.subheadlineSemibold)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var pendingCount: Int {
        environment.writeQueue.pendingCount
    }

    private var shouldShow: Bool {
        !environment.isNetworkAvailable
    }

    private var statusText: String {
        if environment.isOffline {
            return "Offline"
        }
        if environment.writeQueue.isProcessing {
            return "Syncing..."
        }
        return "Pending changes"
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    @ViewBuilder
    private var statusIcon: some View {
        if environment.isOffline {
            Image(systemName: "wifi.slash")
        } else if environment.writeQueue.isProcessing {
            ProgressView()
                .scaleEffect(0.75)
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
    }
}
