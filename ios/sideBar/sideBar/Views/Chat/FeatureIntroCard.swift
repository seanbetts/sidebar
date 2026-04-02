import SwiftUI

struct FeatureIntroCard: View {
    struct Model: Identifiable, Equatable {
        let id: String
        let title: String
        let summary: String
        let systemImage: String
    }

    let feature: Model

    private let cardWidth: CGFloat = 248

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: feature.systemImage)
                .appFont(.headline)
                .foregroundStyle(.primary)
                .frame(width: DesignTokens.Icon.lg, height: DesignTokens.Icon.lg)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(feature.title)
                    .appFont(.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text(feature.summary)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(width: cardWidth, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
