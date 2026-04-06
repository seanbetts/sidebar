import SwiftUI

extension WebsitesDetailView {
    @ViewBuilder
    var pendingWebsiteLoadingView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            LoadingView(message: viewModel.detailLoadingMessage)
            if let pending = viewModel.cancelablePendingWebsite {
                Button("Cancel") {
                    Task { await appEnvironment.cancelPendingWebsite(pending) }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
