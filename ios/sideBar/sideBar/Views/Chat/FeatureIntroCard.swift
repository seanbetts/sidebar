import SwiftUI

struct FeatureIntroCard: View {
    struct Model: Identifiable, Equatable {
        let id: String
        let title: String
        let summary: String
        let systemImage: String
    }

    let feature: Model

    private let cardWidth: CGFloat = 228

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                Image(systemName: feature.systemImage)
                    .appFont(.labelMd)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(width: DesignTokens.Icon.md, height: DesignTokens.Icon.md)
                    .accessibilityHidden(true)

                Text(feature.title)
                    .appFont(.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }

            Text(feature.summary)
                .appFont(.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(width: cardWidth, alignment: .leading)
        .modifier(FeatureIntroCardChrome())
        .accessibilityElement(children: .combine)
    }
}

private struct FeatureIntroCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}
