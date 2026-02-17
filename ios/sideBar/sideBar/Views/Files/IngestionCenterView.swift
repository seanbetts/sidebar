import SwiftUI

struct IngestionCenterView: View {
    @ObservedObject var viewModel: IngestionViewModel

    private var activeItems: [IngestionListItem] {
        viewModel.activeUploadItems
    }

    private var uploadingItems: [IngestionListItem] {
        activeItems.filter(isUploading)
    }

    private var processingItems: [IngestionListItem] {
        activeItems.filter { !isUploading($0) }
    }

    private var failedItems: [IngestionListItem] {
        viewModel.failedUploadItems
    }

    private var hasItems: Bool {
        !uploadingItems.isEmpty || !processingItems.isEmpty || !failedItems.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            summaryCard

            if let ready = viewModel.lastReadyMessage {
                recentReadyCard(message: ready)
            }

            if hasItems {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        if !uploadingItems.isEmpty {
                            section(
                                title: "Uploading",
                                subtitle: "Moving files to workspace",
                                iconName: "arrow.up.circle.fill",
                                tint: DesignTokens.Colors.actionPrimary,
                                items: uploadingItems,
                                section: .uploading
                            )
                        }

                        if !processingItems.isEmpty {
                            section(
                                title: "Processing",
                                subtitle: "Preparing file content",
                                iconName: "gearshape.2.fill",
                                tint: DesignTokens.Colors.textSecondary,
                                items: processingItems,
                                section: .processing
                            )
                        }

                        if !failedItems.isEmpty {
                            section(
                                title: "Needs Attention",
                                subtitle: "Uploads that need a retry or dismissal",
                                iconName: "exclamationmark.triangle.fill",
                                tint: DesignTokens.Colors.warning,
                                items: failedItems,
                                section: .failed
                            )
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(minWidth: 320, maxWidth: 420, maxHeight: 540, alignment: .topLeading)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingestion Center")
                    .font(DesignTokens.Typography.titleMd)
                Spacer()
                if !failedItems.isEmpty {
                    Button("Retry All Failed") {
                        _ = viewModel.retryAllFailedUploads()
                    }
                    .buttonStyle(IngestionCenterActionButtonStyle(tint: DesignTokens.Colors.actionPrimary))
                    .accessibilityLabel("Retry all failed uploads")
                }
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                counterPill(title: "Uploading", value: uploadingItems.count, tint: DesignTokens.Colors.actionPrimary)
                counterPill(title: "Processing", value: processingItems.count, tint: DesignTokens.Colors.textSecondary)
                counterPill(title: "Attention", value: failedItems.count, tint: DesignTokens.Colors.warning)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func section(
        title: String,
        subtitle: String,
        iconName: String,
        tint: Color,
        items: [IngestionListItem],
        section: IngestionCenterSection
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: iconName)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(tint)
                Text(title)
                    .font(DesignTokens.Typography.captionSemibold)
                Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(items.count)")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(.secondary)
            }

            ForEach(items, id: \.file.id) { item in
                IngestionCenterRow(
                    item: item,
                    section: section,
                    canRetry: viewModel.canRetryFailedUpload(fileId: item.file.id),
                    onCancel: { viewModel.cancelUpload(fileId: $0) },
                    onRetry: { viewModel.retryFailedUpload(fileId: $0) },
                    onDismiss: { viewModel.clearFailedUpload(fileId: $0) }
                )
            }
        }
    }

    private func recentReadyCard(message: ReadyFileNotification) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            SuccessCheckBadge(size: 16, symbolSize: 9)
            Text("Ready: \(stripFileExtension(message.filename))")
                .font(DesignTokens.Typography.captionSemibold)
                .lineLimit(1)
            Spacer()
            Button {
                viewModel.clearReadyMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(DesignTokens.Typography.captionSemibold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss ready notification")
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.successBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Label("No active ingestions", systemImage: "tray")
                .font(DesignTokens.Typography.subheadlineSemibold)
            Text("Upload files or paste a YouTube URL to start ingestion.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    private func counterPill(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Circle()
                .fill(tint.opacity(0.8))
                .frame(width: 6, height: 6)
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(DesignTokens.Typography.captionSemibold)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(DesignTokens.Colors.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    private func isUploading(_ item: IngestionListItem) -> Bool {
        let status = [IngestionListItem].normalizedStatus(item.job.status ?? "")
        let stage = [IngestionListItem].normalizedStatus(item.job.stage ?? "")
        return status == "uploading" || stage == "uploading"
    }
}

private enum IngestionCenterSection {
    case uploading
    case processing
    case failed
}

private struct IngestionCenterRow: View {
    let item: IngestionListItem
    let section: IngestionCenterSection
    let canRetry: Bool
    let onCancel: (String) -> Void
    let onRetry: (String) -> Void
    let onDismiss: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
                iconBubble

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(displayName)
                        .font(DesignTokens.Typography.subheadlineSemibold)
                        .lineLimit(1)

                    Text(statusLabel)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)

                    if let detail = statusDetail {
                        Text(detail)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.xs)

                if isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .padding(.top, DesignTokens.Spacing.xxs)
                } else if let progress = clampedProgress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(.secondary)
                } else {
                    LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                }
            }

            if let progress = clampedProgress, !isFailed {
                ProgressView(value: progress)
                    .tint(DesignTokens.Colors.actionPrimary)
            }

            if hasActions {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if canCancel {
                        Button("Cancel") {
                            onCancel(item.file.id)
                        }
                        .buttonStyle(IngestionCenterActionButtonStyle(tint: DesignTokens.Colors.warning))
                        .accessibilityLabel("Cancel upload")
                    }

                    if isFailed {
                        if canRetry {
                            Button("Retry") {
                                onRetry(item.file.id)
                            }
                            .buttonStyle(IngestionCenterActionButtonStyle(tint: DesignTokens.Colors.actionPrimary))
                            .accessibilityLabel("Retry upload")
                        }

                        Button("Dismiss") {
                            onDismiss(item.file.id)
                        }
                        .buttonStyle(IngestionCenterActionButtonStyle(tint: .secondary))
                        .accessibilityLabel("Dismiss failed upload")
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    private var isFailed: Bool {
        [IngestionListItem].normalizedStatus(item.statusValue) == "failed"
    }

    private var canCancel: Bool {
        guard section != .failed else { return false }
        guard item.file.id.hasPrefix("local-") || item.file.id.hasPrefix("youtube-") else { return false }
        let status = [IngestionListItem].normalizedStatus(item.job.status ?? "")
        return status == "uploading" || status == "queued" || status == "processing"
    }

    private var hasActions: Bool {
        canCancel || isFailed
    }

    private var clampedProgress: Double? {
        guard let progress = item.job.progress else { return nil }
        return min(max(progress, 0), 1)
    }

    private var displayName: String {
        let name = stripFileExtension(item.file.filenameOriginal)
        if item.file.mimeOriginal.lowercased() == "video/youtube", name.lowercased() == "youtube video" {
            return "YouTube Video"
        }
        return name
    }

    private var statusLabel: String {
        if isFailed {
            return "Needs attention"
        }
        return ingestionStatusLabel(for: item.job) ?? "Processing"
    }

    private var statusDetail: String? {
        if let message = item.job.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return message
        }
        if let message = item.job.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return message
        }
        return nil
    }

    private var statusColor: Color {
        if isFailed {
            return DesignTokens.Colors.warning
        }
        return .secondary
    }

    private var iconName: String {
        if item.file.category == "folder" {
            return "folder"
        }
        if item.file.mimeOriginal.lowercased().contains("video/youtube") {
            return "video"
        }
        if item.file.category == "presentations" {
            return "rectangle.on.rectangle.angled"
        }
        if item.file.category == "reports" {
            return "chart.line.text.clipboard"
        }
        switch item.recommendedViewer {
        case "viewer_pdf":
            return "doc.richtext"
        case "viewer_json":
            return "tablecells"
        case "viewer_video":
            return "video"
        case "image_original":
            return "photo"
        case "audio_original":
            return "waveform"
        case "viewer_presentation":
            return "rectangle.on.rectangle.angled"
        case "text_original", "ai_md":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private var iconBubble: some View {
        ZStack {
            Circle()
                .fill(iconBackground)
            Image(systemName: iconName)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(iconForeground)
        }
        .frame(width: 30, height: 30)
    }

    private var iconForeground: Color {
        if isFailed {
            return DesignTokens.Colors.warning
        }
        return DesignTokens.Colors.textSecondary
    }

    private var iconBackground: Color {
        if isFailed {
            return DesignTokens.Colors.warningBackground
        }
        return DesignTokens.Colors.muted
    }
}

private struct IngestionCenterActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.captionSemibold)
            .foregroundStyle(tint)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(tint.opacity(configuration.isPressed ? 0.2 : 0.12))
            .clipShape(Capsule())
            .animation(.easeOut(duration: DesignTokens.Animation.quick), value: configuration.isPressed)
    }
}
