import SwiftUI

struct EmptyStateView: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .appFont(.headline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .appFont(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}
