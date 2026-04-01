import SwiftUI

struct OnboardingAddKeyBanner: View {
    let onOpenSettings: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var bannerMaxWidth: CGFloat {
        horizontalSizeClass == .compact ? 360 : 420
    }

    var body: some View {
        GlassEffectContainer(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xsPlus) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "key.horizontal.fill")
                            .appFont(.captionSemibold)
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .leading)
                            .accessibilityHidden(true)

                        Text("Chat needs an API key")
                            .appFont(.labelMd)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.sm)

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .appFont(.captionSemibold)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Settings")
                .modifier(AddKeyBannerButtonChrome())
            }
            .padding(.leading, DesignTokens.Spacing.md)
            .padding(.trailing, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(maxWidth: bannerMaxWidth)
            .modifier(OnboardingAddKeyBannerChromeModifier())
        }
        .accessibilityElement(children: .contain)
    }
}

private struct OnboardingAddKeyBannerChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

private struct AddKeyBannerButtonChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}
