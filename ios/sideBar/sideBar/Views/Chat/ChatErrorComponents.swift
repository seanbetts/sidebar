import SwiftUI

struct ChatErrorPillView: View {
    let presentation: ChatStreamErrorPresentation
    @State private var showPopover = false
    private let maxPillTextWidth: CGFloat = 150
    private let headerPillMinHeight: CGFloat = 22

    var body: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .appFont(.caption2)
                    .foregroundStyle(DesignTokens.Colors.error)
                Text(presentation.pillText)
                    .appFont(.captionSemibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxPillTextWidth, alignment: .leading)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .frame(minHeight: headerPillMinHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignTokens.Colors.surface)
            )
            .overlay(
                Capsule()
                    .stroke(DesignTokens.Colors.error.opacity(0.24), lineWidth: 1)
            )
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds)) {
            MacPopoverShell(type: chatErrorPopoverPanelType()) {
                ChatErrorPopoverContent(presentation: presentation)
            }
            .presentationCompactAdaptation(.sheet)
        }
    }
}

struct ChatErrorPopoverContent: View {
    let presentation: ChatStreamErrorPresentation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.Colors.error)
                    Text(presentation.title)
                        .appFont(.subheadlineSemibold)
                }

                Text(presentation.userMessage)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

                if let requestID = presentation.requestID {
                    detailSection(title: "Request ID", text: requestID)
                }

                if let details = presentation.details, !details.isEmpty {
                    detailSection(title: "Details", text: details)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.captionSemibold)
                .foregroundStyle(.secondary)
            Text(text)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(DesignTokens.Spacing.xsPlus)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
    }
}
