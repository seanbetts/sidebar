import SwiftUI

enum WorkspaceSurfaceActionPresentation: Equatable {
    case singleButton(ToolResultWorkspaceSurfaceTarget)
    case grouped([ToolResultWorkspaceSurfaceTarget])

    static func from(targets: [ToolResultWorkspaceSurfaceTarget]) -> WorkspaceSurfaceActionPresentation? {
        guard !targets.isEmpty else {
            return nil
        }

        if targets.count == 1, let target = targets.first {
            return .singleButton(target)
        }

        return .grouped(targets)
    }
}

struct WorkspaceSurfaceActionGroup: View {
    @EnvironmentObject private var environment: AppEnvironment
    let targets: [ToolResultWorkspaceSurfaceTarget]

    var body: some View {
        Group {
            switch WorkspaceSurfaceActionPresentation.from(targets: targets) {
            case .singleButton(let target):
                actionButton(target)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .grouped(let groupedTargets):
                ChatInlineActionCard(
                    title: "Workspace",
                    subtitle: "Open one of the surfaces produced by this skill"
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        ForEach(groupedTargets) { target in
                            actionButton(target)
                        }
                    }
                }
            case nil:
                EmptyView()
            }
        }
    }

    private func actionButton(_ target: ToolResultWorkspaceSurfaceTarget) -> some View {
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

struct WorkspaceSurfaceInlineActionsBar: View {
    @EnvironmentObject private var environment: AppEnvironment
    let targets: [ToolResultWorkspaceSurfaceTarget]

    var body: some View {
        Group {
            switch WorkspaceSurfaceActionPresentation.from(targets: targets) {
            case .singleButton(let target):
                HStack {
                    Spacer(minLength: 0)
                    actionButton(target, prominent: true)
                        .frame(maxWidth: 280)
                    Spacer(minLength: 0)
                }
            case .grouped(let groupedTargets):
                ChatInlineActionCard(
                    title: "Workspace Handoffs",
                    subtitle: "Open one of the results in the workspace"
                ) {
                    HStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                ForEach(groupedTargets) { target in
                                    actionButton(target, prominent: false)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            case nil:
                EmptyView()
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
