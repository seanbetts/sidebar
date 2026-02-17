import Foundation
import sideBarShared
import SwiftUI

struct ToolCallListView: View {
    let toolCalls: [ToolCall]
    let role: MessageRole
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPopover = false

    var body: some View {
        if toolCalls.count == 1, let toolCall = toolCalls.first {
            toolPill(
                text: toolCall.name,
                showsChevron: false
            )
        } else {
            Button {
                showPopover.toggle()
            } label: {
                toolPill(
                    text: summaryText,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds)) {
                ToolCallPopoverContent(toolCalls: toolCalls)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var summaryText: String {
        let count = toolCalls.count
        if count == 1 {
            return "1 tool used"
        }
        return "\(count) tools used"
    }

    @ViewBuilder
    private func toolPill(
        text: String,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "hammer.fill")
                .font(.caption2)
                .foregroundStyle(toolPillForeground)
            Text(text)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(toolPillForeground)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(toolPillForeground)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(toolPillBackground)
        )
        .overlay(toolPillBorder)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var toolPillBackground: Color {
        if colorScheme == .dark {
            return role == .assistant ? Color.black : Color.white
        }
        return role == .assistant ? Color.white : Color.black
    }

    private var toolPillForeground: Color {
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

struct ToolCallRow: View {
    let toolCall: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(toolCall.name)
                    .font(DesignTokens.Typography.subheadlineSemibold)
                Text(toolCall.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(DesignTokens.Spacing.xsPlus)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground)
        )
    }

    private var statusColor: Color {
        switch toolCall.status {
        case .pending:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var rowBackground: Color {
        DesignTokens.Colors.surface
    }
}

struct ToolCallPopoverContent: View {
    let toolCalls: [ToolCall]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools Used")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(.secondary)
            ForEach(toolCalls) { toolCall in
                ToolCallRow(toolCall: toolCall)
            }
        }
        .padding(DesignTokens.Spacing.xsPlus)
    }
}
