import SwiftUI

struct ChatActiveToolBanner: View {
    let activeTool: ChatActiveTool

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(activeTool.name)
                    .font(DesignTokens.Typography.subheadlineSemibold)
                Text(activeTool.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xsPlus)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bannerBackground: Color {
        DesignTokens.Colors.surface
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch activeTool.status {
        case .running:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
        case .success:
            SuccessCheckBadge(size: 16, symbolSize: 9)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Colors.error)
        }
    }
}

struct PromptPreviewView: View {
    let promptPreview: ChatPromptPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt Preview")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(.secondary)

            if let report = promptPreview.promptReport {
                if let system = report.systemPrompt {
                    Text("System: \(reportSummary(system))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let first = report.firstMessagePrompt {
                    Text("First: \(reportSummary(first))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !promptPreview.systemPromptSections.isEmpty {
                sectionList(
                    title: "System sections",
                    sections: promptPreview.systemPromptSections
                )
            }

            if !promptPreview.firstMessagePromptSections.isEmpty {
                sectionList(
                    title: "First-message sections",
                    sections: promptPreview.firstMessagePromptSections
                )
            }

            if let system = promptPreview.systemPrompt, !system.isEmpty {
                Text(system)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if let first = promptPreview.firstMessagePrompt, !first.isEmpty {
                Text(first)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .padding(DesignTokens.Spacing.xsPlus)
        .background(promptBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var promptBackground: Color {
        DesignTokens.Colors.surface
    }

    private func reportSummary(_ document: ChatPromptReportDocument) -> String {
        let base = "\(document.totalChars)/\(document.maxChars) chars"
        return document.truncated ? "\(base) (truncated)" : base
    }

    @ViewBuilder
    private func sectionList(title: String, sections: [ChatPromptSection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(.secondary)
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                Text("• \(section.id) (\(section.chars))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
