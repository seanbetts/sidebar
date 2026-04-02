import SwiftUI

struct StaticFeatureCarousel: View {
    let onDismiss: () -> Void

    private let features: [FeatureIntroCard.Model] = [
        .init(
            id: "chat",
            title: "Chat",
            summary: "Ask questions, take action, and use skills across your workspace.",
            systemImage: "bubble.left.and.bubble.right"
        ),
        .init(
            id: "notes",
            title: "Notes",
            summary: "Capture ideas, keep scratch work close, and organize it later.",
            systemImage: "note.text"
        ),
        .init(
            id: "tasks",
            title: "Tasks",
            summary: "Track projects, due dates, and follow-up without leaving sideBar.",
            systemImage: "checklist"
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
            systemImage: "square.grid.2x2"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Explore what sideBar can do")
                        .appFont(.headline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)

                    Text("Start anywhere. The rest of the app is already live.")
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer(minLength: DesignTokens.Spacing.sm)

                Button("Not now", action: onDismiss)
                    .buttonStyle(.plain)
                    .appFont(.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .accessibilityLabel("Dismiss feature discovery")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(features) { feature in
                        FeatureIntroCard(feature: feature)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .padding(DesignTokens.Spacing.md)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}
