import Foundation
import SwiftUI

struct ToolCallListView: View {
    let toolCalls: [ToolCall]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tool Calls")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(.secondary)
            ForEach(toolCalls) { toolCall in
                ToolCallRow(toolCall: toolCall)
            }
        }
        .padding(DesignTokens.Spacing.xs)
        .background(toolBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var toolBackground: Color {
        DesignTokens.Colors.surface
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

            if !toolCall.parameters.isEmpty {
                Text(formatJSON(toolCall.parameters.mapValues { $0.value }))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let result = toolCall.result {
                Text(formatJSON(result.value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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

    private func formatJSON(_ value: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let output = String(data: data, encoding: .utf8) {
            return output
        }
        return String(describing: value)
    }
}
