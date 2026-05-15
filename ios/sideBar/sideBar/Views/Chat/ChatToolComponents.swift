import Foundation
import sideBarShared
import SwiftUI

struct ChatToolSummaryPresentation: Equatable {
    let text: String
    let icon: AppIcon
    let hasError: Bool

    var iconName: String {
        icon.rawValue
    }

    static func from(toolCalls: [ToolCall]) -> ChatToolSummaryPresentation {
        let visibleToolCalls = ChatToolPresentation.visibleToolCalls(from: toolCalls)
        let presentedToolCalls = visibleToolCalls.isEmpty ? toolCalls : visibleToolCalls
        let errorCount = presentedToolCalls.filter { $0.status == .error }.count
        let hasError = errorCount > 0

        if presentedToolCalls.count == 1, let toolCall = presentedToolCalls.first {
            let displayName = ChatToolPresentation.displayName(for: toolCall)
            return ChatToolSummaryPresentation(
                text: hasError ? "\(displayName) failed" : displayName,
                icon: hasError
                    ? AppIcon.State.error
                    : SkillIconResolver.appIcon(for: toolCall),
                hasError: hasError
            )
        }

        let icon: AppIcon
        if hasError {
            icon = AppIcon.State.error
        } else {
            let uniqueIcons = Set(presentedToolCalls.map { SkillIconResolver.appIcon(for: $0) })
            icon = uniqueIcons.count == 1 ? uniqueIcons.first ?? AppIcon.Skills.multiple : AppIcon.Skills.multiple
        }

        return ChatToolSummaryPresentation(
            text: "\(presentedToolCalls.count) skills used",
            icon: icon,
            hasError: hasError
        )
    }
}

struct ToolCallListView: View {
    let toolCalls: [ToolCall]
    let role: MessageRole
    @State private var showPopover = false
    private let maxToolPillTextWidth: CGFloat = 120
    private let headerPillMinHeight: CGFloat = 22
    private let popoverWidth: CGFloat = 280
    private var summaryPresentation: ChatToolSummaryPresentation {
        ChatToolSummaryPresentation.from(toolCalls: toolCalls)
    }

    var body: some View {
        Button {
            showPopover = true
        } label: {
            toolPill(text: summaryPresentation.text)
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds)) {
            ToolCallPopoverContent(toolCalls: toolCalls)
                .padding(DesignTokens.Spacing.md)
                .frame(
                    minWidth: popoverWidth,
                    idealWidth: popoverWidth,
                    maxWidth: popoverWidth,
                    alignment: .topLeading
                )
                .presentationCompactAdaptation(.sheet)
        }
    }

    private var summaryIcon: AppIcon {
        summaryPresentation.icon
    }

    @ViewBuilder
    private func toolPill(
        text: String
    ) -> some View {
        MetadataPill(text, maxTitleWidth: maxToolPillTextWidth) {
            SkillSymbolIcon(
                appIcon: summaryIcon,
                appFontStyle: .caption,
                foreground: toolPillForeground
            )
        }
        .frame(minHeight: headerPillMinHeight)
    }

    private var toolPillForeground: Color {
        if summaryPresentation.hasError {
            return DesignTokens.Colors.error
        }
        return DesignTokens.Colors.textSecondary
    }
}

struct ToolCallRow: View {
    let toolCall: ToolCall
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            SkillSymbolIcon(
                appIcon: SkillIconResolver.appIcon(for: toolCall),
                appFontStyle: .caption,
                foreground: .secondary
            )
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(ChatToolPresentation.displayName(for: toolCall))
                .appFont(.subheading)
            Spacer(minLength: 8)
            Text(toolCall.status.rawValue.capitalized)
                .appFont(.caption)
                .foregroundStyle(.secondary)
            if isSelected {
                Image(appIcon: AppIcon.State.successFilled)
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
        case .cancelled:
            return DesignTokens.Colors.textSecondary
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
                        .appFont(.caption)
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
                        status: toolCall.status,
                        isFramed: false
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
