import SwiftUI

struct OfflineBanner: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        if shouldShow {
            HStack(spacing: 8) {
                statusIcon
                Text(statusText)
                    .font(DesignTokens.Typography.subheadlineSemibold)
                if pendingCount > 0 {
                    Text("• \(pendingCount) pending")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.warningBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.top, DesignTokens.Spacing.xs)
        }
    }

    private var pendingCount: Int {
        environment.writeQueue.pendingCount
    }

    private var shouldShow: Bool {
        environment.isOffline || pendingCount > 0
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
