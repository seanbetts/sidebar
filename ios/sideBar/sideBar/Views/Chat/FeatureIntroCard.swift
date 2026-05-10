import SwiftUI

struct FeatureIntroCard: View {
    let feature: OnboardingDiscoveryFeature
    let action: () -> Void

    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    private var textSizeOption: AppTextSizeOption {
        AppTextSizeOption.resolved(from: appTextSizeRaw)
    }

    private var cardWidth: CGFloat {
        244 * textSizeOption.scaleMultiplier
    }

    private var cardHeight: CGFloat {
        152 * textSizeOption.scaleMultiplier
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: feature.systemImage)
                        .appFont(.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .frame(width: DesignTokens.Icon.md, height: DesignTokens.Icon.md)
                        .accessibilityHidden(true)

                    Text(feature.title)
                        .appFont(.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }

                Text(feature.summary)
                    .appFont(.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.md)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .modifier(FeatureIntroCardChrome())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts a guided intro in chat")
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
