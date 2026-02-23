import SwiftUI

struct LoadingView: View {
    let message: String?
    let indicatorSize: CGFloat

    init(message: String? = nil, indicatorSize: CGFloat = LoadingIndicatorSize.page) {
        self.message = message
        self.indicatorSize = indicatorSize
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            LoadingIndicatorView(size: indicatorSize)
            if let message {
                Text(message)
                    .appFont(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}
