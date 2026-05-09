import Foundation
import sideBarShared
import SwiftUI

struct ChatToolSummaryPresentation: Equatable {
    let text: String
    let iconName: String
    let hasError: Bool

    static func from(toolCalls: [ToolCall]) -> ChatToolSummaryPresentation {
        let visibleToolCalls = ChatToolPresentation.visibleToolCalls(from: toolCalls)
        let presentedToolCalls = visibleToolCalls.isEmpty ? toolCalls : visibleToolCalls
        let errorCount = presentedToolCalls.filter { $0.status == .error }.count
        let hasError = errorCount > 0

        if presentedToolCalls.count == 1, let toolCall = presentedToolCalls.first {
            let displayName = ChatToolPresentation.displayName(for: toolCall)
            return ChatToolSummaryPresentation(
                text: hasError ? "\(displayName) failed" : displayName,
                iconName: hasError
                    ? "exclamationmark.circle"
                    : SkillIconResolver.iconName(for: toolCall),
                hasError: hasError
            )
        }

        let iconName: String
        if hasError {
            iconName = "exclamationmark.circle"
        } else {
            let uniqueIcons = Set(presentedToolCalls.map { SkillIconResolver.iconName(for: $0) })
            iconName = uniqueIcons.count == 1 ? uniqueIcons.first ?? "square.stack.3d.up" : "square.stack.3d.up"
        }

        return ChatToolSummaryPresentation(
            text: "\(presentedToolCalls.count) skills used",
            iconName: iconName,
            hasError: hasError
        )
    }
}

struct ToolCallListView: View {
    let toolCalls: [ToolCall]
    let role: MessageRole
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPopover = false
    private let maxToolPillTextWidth: CGFloat = 120
    private let headerPillMinHeight: CGFloat = 22
    private var summaryPresentation: ChatToolSummaryPresentation {
        ChatToolSummaryPresentation.from(toolCalls: toolCalls)
    }

    var body: some View {
        Button {
            showPopover = true
        } label: {
            ViewThatFits(in: .horizontal) {
                toolPill(text: summaryPresentation.text)
                toolIconOnlyPill
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds)) {
            MacPopoverShell(type: toolCallPopoverPanelType()) {
                ToolCallPopoverContent(toolCalls: toolCalls)
            }
            .presentationCompactAdaptation(.sheet)
        }
    }

    private var summaryIconName: String {
        summaryPresentation.iconName
    }

    @ViewBuilder
    private func toolPill(
        text: String
    ) -> some View {
        HStack(spacing: 6) {
            SkillSymbolIcon(
                systemName: summaryIconName,
                appFontStyle: .caption2,
                foreground: toolPillForeground
            )
            Text(text)
                .appFont(.captionSemibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxToolPillTextWidth, alignment: .leading)
                .foregroundStyle(toolPillForeground)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .frame(minHeight: headerPillMinHeight)
        .background(
            Capsule(style: .continuous)
                .fill(toolPillBackground)
        )
        .overlay(toolPillBorder)
    }

    private var toolIconOnlyPill: some View {
        SkillSymbolIcon(
            systemName: summaryIconName,
            appFontStyle: .caption2,
            foreground: toolPillForeground
        )
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .frame(minHeight: headerPillMinHeight)
        .background(
            Capsule(style: .continuous)
                .fill(toolPillBackground)
        )
        .overlay(toolPillBorder)
    }

    private var toolPillBackground: Color {
        if colorScheme == .dark {
            return role == .assistant ? Color.black : Color.white
        }
        return role == .assistant ? Color.white : Color.black
    }

    private var toolPillForeground: Color {
        if summaryPresentation.hasError {
            return DesignTokens.Colors.error
        }
        if colorScheme == .dark {
            return role == .assistant ? Color.white : Color.black
        }
        return role == .assistant ? Color.black : Color.white
    }

    @ViewBuilder
    private var toolPillBorder: some View {
        if colorScheme == .light, role == .assistant {
            Capsule()
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        }
    }
}

struct ChatToolActionListView: View {
    let actions: [ChatToolAction]
    let onAction: (ChatToolAction, ChatToolActionDecision?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions) { action in
                ChatToolActionCard(action: action, onAction: onAction)
            }
        }
    }
}

struct ChatToolActionCard: View {
    let action: ChatToolAction
    let onAction: (ChatToolAction, ChatToolActionDecision?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                SkillSymbolIcon(
                    systemName: iconName,
                    appFontStyle: .subheadline,
                    foreground: iconForeground
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.summary)
                        .appFont(.subheadlineSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    if let supportingText {
                        Text(supportingText)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
            }
            actionControls
        }
        .padding(DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionControls: some View {
        switch action.kind {
        case .confirmation:
            confirmationControls
        case .undo:
            undoControls
        }
    }

    private var confirmationControls: some View {
        HStack(spacing: 8) {
            Button {
                onAction(action, .decline)
            } label: {
                Label("Decline", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .disabled(!isPending)

            Button {
                onAction(action, .accept)
            } label: {
                Label("Confirm", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isPending)

            statusLabel
        }
    }

    private var undoControls: some View {
        HStack(spacing: 8) {
            Button {
                onAction(action, nil)
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!isPending)

            statusLabel
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if action.status != .pending {
            Text(statusText)
                .appFont(.captionSemibold)
                .foregroundStyle(statusForeground)
        }
    }

    private var supportingText: String? {
        if action.status == .running {
            return "Working..."
        }
        if action.status == .failed {
            return "Action failed. Try again."
        }
        if let guardReason = action.guardReason, !guardReason.isEmpty {
            return guardReason
        }
        if action.kind == .confirmation, action.undoSupported {
            return "Undo will be available briefly after this runs."
        }
        return nil
    }

    private var iconName: String {
        switch action.kind {
        case .confirmation:
            return "exclamationmark.triangle"
        case .undo:
            return "arrow.uturn.backward.circle"
        }
    }

    private var iconForeground: Color {
        action.status == .failed ? DesignTokens.Colors.error : DesignTokens.Colors.textSecondary
    }

    private var isPending: Bool {
        action.status == .pending
    }

    private var statusText: String {
        switch action.status {
        case .pending:
            return ""
        case .running:
            return "Working"
        case .accepted:
            return "Confirmed"
        case .declined:
            return "Declined"
        case .undone:
            return "Undone"
        case .failed:
            return "Failed"
        }
    }

    private var statusForeground: Color {
        action.status == .failed ? DesignTokens.Colors.error : DesignTokens.Colors.textSecondary
    }
}

struct ToolCallRow: View {
    let toolCall: ToolCall
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            SkillSymbolIcon(
                systemName: SkillIconResolver.iconName(for: toolCall),
                appFontStyle: .caption,
                foreground: .secondary
            )
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(ChatToolPresentation.displayName(for: toolCall))
                .appFont(.subheadlineSemibold)
            Spacer(minLength: 8)
            Text(toolCall.status.rawValue.capitalized)
                .appFont(.caption)
                .foregroundStyle(.secondary)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Spacing.xsPlus)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(rowBorder, lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch toolCall.status {
        case .pending:
            return DesignTokens.Colors.textSecondary
        case .success:
            return DesignTokens.Colors.textPrimary
        case .error:
            return DesignTokens.Colors.error
        }
    }

    private var rowBackground: Color {
        isSelected ? DesignTokens.Colors.muted : DesignTokens.Colors.surface
    }

    private var rowBorder: Color {
        isSelected ? DesignTokens.Colors.border : .clear
    }
}

struct ToolCallPopoverContent: View {
    let toolCalls: [ToolCall]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if ChatToolPresentation.usesListOnlyPopoverLayout(for: toolCalls) {
                    Text("Skills Used")
                        .appFont(.captionSemibold)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(visibleToolCalls) { toolCall in
                            ToolCallRow(
                                toolCall: toolCall,
                                isSelected: false
                            )
                        }
                    }
                } else if let selectedToolCall {
                    ToolCallDetailView(toolCall: selectedToolCall)
                } else {
                    Text("No skill details available.")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var visibleToolCalls: [ToolCall] {
        let visibleToolCalls = ChatToolPresentation.visibleToolCalls(from: toolCalls)
        return visibleToolCalls.isEmpty ? toolCalls : visibleToolCalls
    }

    private var selectedToolCall: ToolCall? {
        visibleToolCalls.first
    }
}

struct ToolCallDetailView: View {
    let toolCall: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(detailSections) { section in
                switch section.kind {
                case .summary:
                    ToolCallSummaryCard(
                        summary: summaryPresentation,
                        status: toolCall.status
                    )
                case .workspaceActions:
                    if !workspaceSurfaceTargets.isEmpty {
                        WorkspaceSurfaceActionGroup(targets: workspaceSurfaceTargets)
                    }
                }
            }
        }
    }

    private var detailSections: [ChatToolDetailSection] {
        ChatToolPresentation.detailSections(for: toolCall)
    }

    private var summaryPresentation: ChatToolPresentation.Summary {
        ChatToolPresentation.summary(for: toolCall)
    }

    private var workspaceSurfaceTargets: [ToolResultWorkspaceSurfaceTarget] {
        ToolResultWorkspaceSurfaceParser.parse(toolCall)
    }
}
