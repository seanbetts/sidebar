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
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
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
}
