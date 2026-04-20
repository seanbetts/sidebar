import SwiftUI

struct WorkspaceSurfaceActionGroup: View {
    @EnvironmentObject private var environment: AppEnvironment
    let targets: [ToolResultWorkspaceSurfaceTarget]

    var body: some View {
        ChatInlineActionCard(
            title: "Workspace",
            subtitle: targets.count == 1
                ? "Open the surface produced by this skill"
                : "Open one of the surfaces produced by this skill"
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(targets) { target in
                    Button {
                        environment.presentAgentSurface(
                            target.surface,
                            in: target.pane,
                            source: "chat_workspace_surface_link"
                        )
                    } label: {
                        Label(target.label, systemImage: target.iconName)
                            .appFont(.captionSemibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct WorkspaceSurfaceInlineActionsBar: View {
    @EnvironmentObject private var environment: AppEnvironment
    let targets: [ToolResultWorkspaceSurfaceTarget]

    var body: some View {
        ChatInlineActionCard(
            title: targets.count == 1 ? "Workspace Handoff" : "Workspace Handoffs",
            subtitle: targets.count == 1
                ? "Open the result in the workspace"
                : "Open one of the results in the workspace"
        ) {
            Group {
                if targets.count == 1, let target = targets.first {
                    HStack {
                        Spacer(minLength: 0)
                        actionButton(target, prominent: true)
                            .frame(maxWidth: 280)
                        Spacer(minLength: 0)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            ForEach(targets) { target in
                                actionButton(target, prominent: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func actionButton(
        _ target: ToolResultWorkspaceSurfaceTarget,
        prominent: Bool
    ) -> some View {
        if prominent {
            Button {
                environment.presentAgentSurface(
                    target.surface,
                    in: target.pane,
                    source: "chat_workspace_surface_inline"
                )
            } label: {
                Label(target.label, systemImage: target.iconName)
                    .appFont(.captionSemibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .controlSize(.regular)
        } else {
            Button {
                environment.presentAgentSurface(
                    target.surface,
                    in: target.pane,
                    source: "chat_workspace_surface_inline"
                )
            } label: {
                Label(target.label, systemImage: target.iconName)
                    .appFont(.captionSemibold)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .controlSize(.regular)
        }
    }
}

struct ToolCallSummaryCard: View {
    let summary: ChatToolPresentation.Summary
    let status: ToolStatus

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                Text(summary.primaryText)
                    .appFont(.subheadlineSemibold)
                    .foregroundStyle(statusForeground)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text(status.rawValue.capitalized)
                    .appFont(.caption2Semibold)
                    .foregroundStyle(statusForeground)
            }

            if let secondaryText = summary.secondaryText {
                Text(secondaryText)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    private var statusForeground: Color {
        switch status {
        case .pending:
            return DesignTokens.Colors.textSecondary
        case .success:
            return DesignTokens.Colors.textPrimary
        case .error:
            return DesignTokens.Colors.error
        }
    }
}

struct ToolCallDisclosureCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        subtitle: String?,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            DisclosureGroup(isExpanded: $isExpanded) {
                content
                    .padding(.top, DesignTokens.Spacing.xs)
            } label: {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                    Text(title)
                        .appFont(.subheadlineSemibold)

                    if let subtitle {
                        Text(subtitle)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(DesignTokens.Colors.textPrimary)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }
}

struct ToolCallTechnicalDetailView: View {
    let detail: ChatToolTechnicalDetail

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if !detail.parameterRows.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Parameters")
                        .appFont(.captionSemibold)
                        .foregroundStyle(.secondary)

                    ForEach(detail.parameterRows) { item in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                            Text(item.key)
                                .appFont(.captionSemibold)
                                .foregroundStyle(.secondary)
                            Text(item.value)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if let resultText = detail.resultText {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Result")
                        .appFont(.captionSemibold)
                        .foregroundStyle(.secondary)
                    Text(resultText)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
