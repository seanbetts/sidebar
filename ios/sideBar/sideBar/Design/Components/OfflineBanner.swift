import SwiftUI

struct OfflineBanner: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPendingWritesPresented = false

    var body: some View {
        if shouldShow {
            Button {
                isPendingWritesPresented = true
            } label: {
                HStack(spacing: 6) {
                    statusIcon
                    Text(statusText)
                        .font(DesignTokens.Typography.captionSemibold)
                }
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                #if !os(macOS)
                .padding(.vertical, -4)
                #endif
            }
            .buttonStyle(.plain)
            .accessibilityLabel(statusText)
            .sheet(isPresented: $isPendingWritesPresented) {
                NavigationStack {
                    PendingWritesView()
                }
            }
        }
    }

    private var pendingCount: Int {
        environment.writeQueue.pendingCount
    }

    private var shouldShow: Bool {
        environment.isOffline || environment.writeQueue.isProcessing || pendingCount > 0
    }

    private var statusText: String {
        if environment.isOffline {
            return "Offline"
        }
        if environment.writeQueue.isProcessing {
            return "Syncing \(pendingCount) changes"
        }
        return "\(pendingCount) pending changes"
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
