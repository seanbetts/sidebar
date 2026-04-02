import SwiftUI

struct StaticFeatureCarousel: View {
    let onSelectFeature: (OnboardingDiscoveryFeature) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isExpanded = false

    private let features = OnboardingDiscoveryFeature.allCases

    private var panelMaxWidth: CGFloat {
        horizontalSizeClass == .compact ? 360 : 460
    }

    private var previewSummary: String {
        "Chat, notes, tasks, and more"
    }

    var body: some View {
        GlassEffectContainer(spacing: DesignTokens.Spacing.xs) {
            VStack(alignment: .leading, spacing: isExpanded ? DesignTokens.Spacing.md : DesignTokens.Spacing.xs) {
                header

                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: panelMaxWidth, alignment: .leading)
            .modifier(FeatureDiscoveryPanelChrome())
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            Button(action: toggleExpanded) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .appFont(.captionSemibold)
                        .foregroundStyle(.secondary)
                        .frame(width: DesignTokens.Icon.md, height: DesignTokens.Icon.md)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                        Text("Explore sideBar")
                            .appFont(.labelMd)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)

                        if !isExpanded {
                            Text(previewSummary)
                                .appFont(.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse feature discovery" : "Expand feature discovery")

            HStack(spacing: DesignTokens.Spacing.xs) {
                Button(action: toggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .appFont(.captionSemibold)
                        .frame(width: DesignTokens.Icon.xl, height: DesignTokens.Icon.xl)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse feature discovery" : "Expand feature discovery")
                .modifier(FeatureDiscoveryIconButtonChrome())

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .appFont(.captionSemibold)
                        .frame(width: DesignTokens.Icon.xl, height: DesignTokens.Icon.xl)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss feature discovery")
                .modifier(FeatureDiscoveryIconButtonChrome())
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Start anywhere. The rest of the app is already live.")
                .appFont(.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(features) { feature in
                        FeatureIntroCard(feature: feature) {
                            onSelectFeature(feature)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xxxs)
                .padding(.trailing, DesignTokens.Spacing.md)
            }
        }
    }

    private func toggleExpanded() {
        withAnimation(Motion.standard(reduceMotion: reduceMotion)) {
            isExpanded.toggle()
        }
    }
}

private struct FeatureDiscoveryPanelChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

private struct FeatureDiscoveryIconButtonChrome: ViewModifier {
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
