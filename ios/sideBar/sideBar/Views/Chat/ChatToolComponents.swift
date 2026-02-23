import Foundation
import sideBarShared
import SwiftUI

struct ToolCallListView: View {
    let toolCalls: [ToolCall]
    let role: MessageRole
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPopover = false
    private let maxToolPillTextWidth: CGFloat = 120
    private let headerPillMinHeight: CGFloat = 22

    var body: some View {
        Button {
            showPopover = true
        } label: {
            ViewThatFits(in: .horizontal) {
                toolPill(text: summaryText)
                toolIconOnlyPill
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds)) {
            ToolCallPopoverContent(toolCalls: toolCalls)
                .presentationCompactAdaptation(.sheet)
        }
    }

    private var summaryText: String {
        if toolCalls.count == 1, let toolCall = toolCalls.first {
            return toolCall.name
        }
        return "\(toolCalls.count) skills used"
    }

    private var summaryIconName: String {
        guard !toolCalls.isEmpty else {
            return "puzzlepiece.extension"
        }
        if toolCalls.count == 1, let toolCall = toolCalls.first {
            return SkillIconResolver.iconName(for: toolCall)
        }
        let uniqueIcons = Set(toolCalls.map { SkillIconResolver.iconName(for: $0) })
        if uniqueIcons.count == 1, let icon = uniqueIcons.first {
            return icon
        }
        return "square.stack.3d.up"
    }

    @ViewBuilder
    private func toolPill(
        text: String
    ) -> some View {
        HStack(spacing: 6) {
            SkillSymbolIcon(
                systemName: summaryIconName,
                font: .caption2,
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
            font: .caption2,
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
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            SkillSymbolIcon(
                systemName: SkillIconResolver.iconName(for: toolCall),
                font: .caption,
                foreground: .secondary
            )
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(toolCall.name)
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
    @State private var selectedToolCallID: String

    init(toolCalls: [ToolCall]) {
        self.toolCalls = toolCalls
        _selectedToolCallID = State(initialValue: toolCalls.first?.id ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Skills Used")
                    .appFont(.captionSemibold)
                    .foregroundStyle(.secondary)

                if toolCalls.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(toolCalls) { toolCall in
                            Button {
                                selectedToolCallID = toolCall.id
                            } label: {
                                ToolCallRow(
                                    toolCall: toolCall,
                                    isSelected: selectedToolCallID == toolCall.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider()
                }

                if let selectedToolCall {
                    ToolCallDetailView(toolCall: selectedToolCall)
                } else {
                    Text("No skill details available.")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DesignTokens.Spacing.xsPlus)
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, alignment: .topLeading)
    }

    private var selectedToolCall: ToolCall? {
        toolCalls.first(where: { $0.id == selectedToolCallID }) ?? toolCalls.first
    }
}

struct ToolCallDetailView: View {
    let toolCall: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolCallRow(toolCall: toolCall, isSelected: true)
                .allowsHitTesting(false)
            if let promptPreview = PromptPreviewPayloadParser.parseToolResult(toolCall.result) {
                PromptPreviewView(promptPreview: promptPreview)
            } else {
                fallbackDetail
            }
        }
    }

    private var fallbackDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !toolCall.parameters.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parameters")
                        .appFont(.captionSemibold)
                        .foregroundStyle(.secondary)
                    ForEach(parameterRows, id: \.key) { item in
                        Text("\(item.key): \(item.value)")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if let summary = resultSummaryText {
                Text(summary)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(DesignTokens.Spacing.xsPlus)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
    }

    private var parameterRows: [(key: String, value: String)] {
        toolCall.parameters
            .map { (key: $0.key, value: formattedValue($0.value.value)) }
            .sorted { $0.key < $1.key }
    }

    private var resultSummaryText: String? {
        guard let resultValue = toolCall.result?.value else {
            return nil
        }
        guard let resultPayload = resultValue as? [String: Any] else {
            return formattedValue(resultValue)
        }
        if let error = resultPayload["error"] as? String, !error.isEmpty {
            return error
        }
        if let success = resultPayload["success"] as? Bool {
            return success ? "Skill completed successfully." : "Skill failed."
        }
        if let data = resultPayload["data"] {
            return formattedValue(data)
        }
        return formattedValue(resultPayload)
    }

    private func formattedValue(_ value: Any) -> String {
        if let stringValue = value as? String {
            return stringValue
        }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return String(describing: value)
    }
}
