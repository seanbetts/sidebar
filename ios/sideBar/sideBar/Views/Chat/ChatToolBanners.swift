import SwiftUI

struct ChatActiveToolBanner: View {
    let activeTool: ChatActiveTool

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(activeTool.name)
                    .appFont(.subheadlineSemibold)
                Text(activeTool.status.rawValue.capitalized)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xsPlus)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bannerBackground: Color {
        DesignTokens.Colors.surface
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch activeTool.status {
        case .running:
            LoadingIndicatorView(size: LoadingIndicatorSize.inline)
        case .success:
            SuccessCheckBadge(size: 16, symbolSize: 9)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Colors.error)
        }
    }
}
