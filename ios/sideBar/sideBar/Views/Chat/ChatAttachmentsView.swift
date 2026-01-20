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
                        .font(.system(size: 14, weight: .semibold))
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
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Retry attachment")
                            Button {
                                onDelete(attachment.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete attachment")
                        }
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                            .font(.system(size: 12, weight: .semibold))
                        Text(attachment.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
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
