import SwiftUI

struct PendingAttachmentsView: View {
    let attachments: [ChatAttachmentItem]
    let onRetry: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(attachments) { attachment in
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                        .font(DesignTokens.Typography.labelMd)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(statusText(for: attachment))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if attachment.status == .failed {
                        HStack(spacing: 8) {
                            Button {
                                onRetry(attachment.id)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(DesignTokens.Typography.labelMd)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Retry attachment")
                            Button {
                                onDelete(attachment.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(DesignTokens.Typography.labelMd)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete attachment")
                        }
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
            }
        }
    }

    private func statusText(for attachment: ChatAttachmentItem) -> String {
        if let stage = attachment.stage, !stage.isEmpty {
            return stage
        }
        switch attachment.status {
        case .uploading:
            return "uploading"
        case .queued:
            return "queued"
        case .failed:
            return "failed"
        case .canceled:
            return "canceled"
        case .ready:
            return "ready"
        }
    }
}

struct ReadyAttachmentsView: View {
    let attachments: [ChatAttachmentItem]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(DesignTokens.Typography.labelXs)
                        Text(attachment.name)
                            .font(DesignTokens.Typography.captionSemibold)
                            .lineLimit(1)
                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(DesignTokens.Typography.labelXxs)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .padding(.horizontal, DesignTokens.Spacing.xsPlus)
                    .padding(.vertical, DesignTokens.Spacing.xxsPlus)
                    .background(DesignTokens.Colors.muted)
                    .clipShape(Capsule())
                }
            }
        }
    }
}

struct AttachmentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
