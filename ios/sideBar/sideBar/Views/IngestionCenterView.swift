import SwiftUI

struct IngestionCenterView: View {
    let activeItems: [IngestionListItem]
    let failedItems: [IngestionListItem]
    let onCancel: (IngestionListItem) -> Void
    let onClearFailure: (IngestionListItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ingestion Center")
                .font(.headline)

            if activeItems.isEmpty && failedItems.isEmpty {
                Text("No active uploads.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !activeItems.isEmpty {
                            section(title: "Active", items: activeItems, showCancel: true, showClear: false)
                        }
                        if !failedItems.isEmpty {
                            section(title: "Failed", items: failedItems, showCancel: false, showClear: true)
                        }
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(minWidth: 280, maxWidth: 360, maxHeight: 420)
    }

    @ViewBuilder
    private func section(title: String, items: [IngestionListItem], showCancel: Bool, showClear: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(.secondary)
            ForEach(items, id: \.file.id) { item in
                IngestionCenterRow(
                    item: item,
                    showCancel: showCancel,
                    showClear: showClear,
                    onCancel: onCancel,
                    onClear: onClearFailure
                )
            }
        }
    }
}

private struct IngestionCenterRow: View {
    let item: IngestionListItem
    let showCancel: Bool
    let showClear: Bool
    let onCancel: (IngestionListItem) -> Void
    let onClear: (IngestionListItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(stripFileExtension(item.file.filenameOriginal))
                    .font(DesignTokens.Typography.subheadlineSemibold)
                    .lineLimit(1)
                Spacer()
                if isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if showCancel && isCancellable {
                    Button {
                        onCancel(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(DesignTokens.Typography.captionSemibold)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel upload")
                }
                if showClear && isFailed {
                    Button {
                        onClear(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(DesignTokens.Typography.captionSemibold)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear failed upload")
                }
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !isFailed {
                if let progress = item.job.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                }
            }
        }
        .padding(DesignTokens.Spacing.xsPlus)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    private var isLocalPlaceholder: Bool {
        item.file.id.hasPrefix("local-") || item.file.id.hasPrefix("youtube-")
    }

    private var isCancellable: Bool {
        guard isLocalPlaceholder else { return false }
        let status = (item.job.status ?? "").lowercased()
        return status == "uploading" || status == "queued" || status == "processing"
    }

    private var isFailed: Bool {
        (item.job.status ?? "") == "failed"
    }

    private var statusText: String {
        if let message = item.job.userMessage, !message.isEmpty {
            return message
        }
        return ingestionStatusLabel(for: item.job) ?? "Processing"
    }
}
