import SwiftUI

struct StaticFeatureCarousel: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isExpanded = false

    private let features: [FeatureIntroCard.Model] = [
        .init(
            id: "chat",
            title: "Chat",
            summary: "Ask questions, take action, and use skills across your workspace.",
            systemImage: "bubble"
        ),
        .init(
            id: "notes",
            title: "Notes",
            summary: "Capture ideas, keep scratch work close, and organize them later.",
            systemImage: "text.document"
        ),
        .init(
            id: "tasks",
            title: "Tasks",
            summary: "Track projects, due dates, and follow-up without leaving sideBar.",
            systemImage: "checkmark.square"
        ),
        .init(
            id: "websites",
            title: "Websites",
            summary: "Save articles and links so the assistant can reference them later.",
            systemImage: "globe"
        ),
        .init(
            id: "files",
            title: "Files",
            summary: "Upload PDFs and documents, then search or ask questions about them.",
            systemImage: "folder"
        ),
        .init(
            id: "skills",
            title: "Skills",
            summary: "Extend what the assistant can do with built-in and store skills.",
            systemImage: "command.circle"
        )
    ]

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
                        FeatureIntroCard(feature: feature)
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
