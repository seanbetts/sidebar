import SwiftUI

extension WebsitesDetailView {
    @ViewBuilder
    var pendingWebsiteLoadingView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            LoadingView(message: viewModel.detailLoadingMessage)
            if viewModel.canCancelWebsiteSave() {
                Button("Cancel") {
                    Task { await viewModel.cancelWebsiteSave() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
