import SwiftUI

struct SyncStatusIndicator: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isPulsing = false

    var body: some View {
        if environment.writeQueue.pendingCount > 0 {
            ZStack {
                Circle()
                    .fill(environment.writeQueue.isProcessing ? DesignTokens.Colors.success : DesignTokens.Colors.warning)
                    .frame(width: 8, height: 8)
                if environment.writeQueue.isProcessing {
                    Circle()
                        .stroke(DesignTokens.Colors.success.opacity(0.5), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .scaleEffect(isPulsing ? 1.2 : 0.9)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isPulsing)
                }
            }
            .onAppear {
                isPulsing = true
            }
            .onChange(of: environment.writeQueue.isProcessing) { _, isProcessing in
                if isProcessing {
                    isPulsing = true
                } else {
                    isPulsing = false
                }
            }
            .accessibilityLabel(syncAccessibilityLabel)
        }
    }

    private var syncAccessibilityLabel: String {
        environment.writeQueue.isProcessing ? "Syncing pending changes" : "Pending changes"
    }
}
