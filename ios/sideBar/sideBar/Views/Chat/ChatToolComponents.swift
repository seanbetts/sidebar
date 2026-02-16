import Foundation
import sideBarShared
import SwiftUI

struct ToolCallListView: View {
    let toolCalls: [ToolCall]
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(summaryText)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.xs)
            .background(toolBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds)) {
            ToolCallPopoverContent(toolCalls: toolCalls)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var toolBackground: Color {
        DesignTokens.Colors.surface
    }

    private var summaryText: String {
        let count = toolCalls.count
        if count == 1 {
            return "1 tool used"
        }
        return "\(count) tools used"
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
