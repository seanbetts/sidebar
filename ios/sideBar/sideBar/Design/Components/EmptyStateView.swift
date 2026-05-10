import SwiftUI

struct EmptyStateView: View {
    let title: String
    let subtitle: String?
    let systemImage: String?

    init(title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .appScaledFont(size: DesignTokens.Icon.lg, weight: .medium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: DesignTokens.Icon.xxl, height: DesignTokens.Icon.xxl)
                    .background(
                        Circle()
                            .fill(DesignTokens.Colors.muted.opacity(0.55))
                    )
                    .accessibilityHidden(true)
            }
            Text(title)
                .appFont(.subheading)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .appFont(.subheading)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}
