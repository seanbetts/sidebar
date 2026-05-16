import SwiftUI
import sideBarShared

struct StaticFeatureCarousel: View {
    let onSelectFeature: (OnboardingDiscoveryFeature) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var isPreviewSummaryVisible = true
    @State private var previewSummaryRevealTask: Task<Void, Never>?
    @State private var isTitleInExpandedPosition = false

    private let features = OnboardingDiscoveryFeature.allCases

    private var previewSummary: String {
        "Notes, tasks, websites, and more"
    }

    var body: some View {
        GlassEffectContainer(spacing: DesignTokens.Spacing.xs) {
            VStack(alignment: .leading, spacing: isExpanded ? DesignTokens.Spacing.md : DesignTokens.Spacing.xs) {
                header

                if isExpanded {
                    expandedContent
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        )
                }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .modifier(FeatureDiscoveryPanelChrome())
        }
        .accessibilityElement(children: .contain)
        .onDisappear {
            previewSummaryRevealTask?.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Button(action: toggleExpanded) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(appIcon: AppIcon.Onboarding.featureDiscovery)
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: DesignTokens.Icon.md, height: DesignTokens.Icon.md)
                        .offset(y: isTitleInExpandedPosition ? DesignTokens.Spacing.xxxs : 0)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                        Text("Explore sideBar")
                            .appFont(.titleMd)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)
                            .offset(y: isTitleInExpandedPosition ? DesignTokens.Spacing.xxxs : 0)

                        if isPreviewSummaryVisible {
                            Text(previewSummary)
                                .appFont(.body)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .lineLimit(1)
                                .transition(.identity)
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
                    Image(appIcon: isExpanded ? AppIcon.Navigation.chevronUp : AppIcon.Navigation.chevronDown)
                        .appFont(.caption)
                        .frame(width: DesignTokens.Icon.xl, height: DesignTokens.Icon.xl)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse feature discovery" : "Expand feature discovery")
                .modifier(FeatureDiscoveryIconButtonChrome())

                Button(action: onDismiss) {
                    Image(appIcon: AppIcon.Action.close)
                        .appFont(.caption)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(features) { feature in
                        FeatureIntroCard(feature: feature) {
                            collapseExpandedContent()
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
        previewSummaryRevealTask?.cancel()

        if isExpanded {
            collapseExpandedContent()
        } else {
            setPreviewSummaryVisible(false)
            withAnimation(Motion.slow(reduceMotion: reduceMotion)) {
                isTitleInExpandedPosition = true
            }

            withAnimation(Motion.standard(reduceMotion: reduceMotion)) {
                isExpanded = true
            }
        }
    }

    private func collapseExpandedContent() {
        previewSummaryRevealTask?.cancel()

        withAnimation(Motion.slow(reduceMotion: reduceMotion)) {
            isTitleInExpandedPosition = false
        }

        withAnimation(Motion.standard(reduceMotion: reduceMotion)) {
            isExpanded = false
        }

        if reduceMotion {
            setPreviewSummaryVisible(true)
        } else {
            previewSummaryRevealTask = Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(DesignTokens.Animation.slow * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    setPreviewSummaryVisible(true)
                }
            }
        }
    }

    private func setPreviewSummaryVisible(_ isVisible: Bool) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isPreviewSummaryVisible = isVisible
        }
    }
}

private struct FeatureDiscoveryPanelChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.glassChrome(.extraLargeCard)
    }
}

private struct FeatureDiscoveryIconButtonChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.glassChrome(.pill)
    }
}
