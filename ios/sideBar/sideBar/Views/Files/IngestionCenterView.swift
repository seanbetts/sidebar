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

    private var displayItems: [IngestionListItem] {
        uploadingItems + processingItems + failedItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Ingestion Centre")
                .appFont(.subheading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            if displayItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(displayItems.indices, id: \.self) { index in
                            let item = displayItems[index]
                            IngestionCenterRow(
                                item: item,
                                canCancel: viewModel.canCancelIngestion(fileId: item.file.id),
                                canRetry: viewModel.canRetryFailedUpload(fileId: item.file.id),
                                onCancel: { viewModel.cancelIngestion(fileId: $0) },
                                onRetry: { viewModel.retryFailedUpload(fileId: $0) },
                                onDismiss: { viewModel.clearFailedUpload(fileId: $0) }
                            )

                            if index < displayItems.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 540, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Label("No active ingestions", systemImage: "tray")
                .appFont(.subheading)
            Text("Upload files or paste a YouTube URL to start ingestion.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private func isUploading(_ item: IngestionListItem) -> Bool {
        let status = [IngestionListItem].normalizedStatus(item.job.status ?? "")
        let stage = [IngestionListItem].normalizedStatus(item.job.stage ?? "")
        return status == "uploading" || stage == "uploading"
    }
}

private struct IngestionCenterRow: View {
    let item: IngestionListItem
    let canCancel: Bool
    let canRetry: Bool
    let onCancel: (String) -> Void
    let onRetry: (String) -> Void
    let onDismiss: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.xs) {
                leadingIndicator
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(displayName)
                        .appFont(.subheading)
                        .lineLimit(1)

                    Text(metadataText)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: DesignTokens.Spacing.xs)

                HStack(spacing: DesignTokens.Spacing.xs) {
                    trailingStatus

                    if isFailed, canRetry {
                        Button("Retry") {
                            onRetry(item.file.id)
                        }
                        .buttonStyle(IngestionCenterActionButtonStyle())
                        .accessibilityLabel("Retry upload")
                    }

                    if isFailed {
                        Button("Dismiss") {
                            onDismiss(item.file.id)
                        }
                        .buttonStyle(IngestionCenterActionButtonStyle())
                        .accessibilityLabel("Dismiss failed upload")
                    }

                    if canCancel {
                        Button("Cancel") {
                            onCancel(item.file.id)
                        }
                        .buttonStyle(IngestionCenterActionButtonStyle())
                        .accessibilityLabel("Cancel upload")
                    }
                }
            }

            if let progress = clampedProgress, !isFailed {
                ProgressView(value: progress)
                    .tint(DesignTokens.Colors.textPrimary)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if isLoadingState {
            LoadingIndicatorView(size: LoadingIndicatorSize.inline)
        } else {
            Image(systemName: iconName)
                .appFont(.subheading)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if let progress = clampedProgress {
            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .appFont(.caption)
                .foregroundStyle(.secondary)
        } else if isFailed {
            Image(systemName: "exclamationmark")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isFailed: Bool {
        [IngestionListItem].normalizedStatus(item.statusValue) == "failed"
    }

    private var isLoadingState: Bool {
        let normalizedStatus = [IngestionListItem].normalizedStatus(item.statusValue)
        return !normalizedStatus.isEmpty &&
            ![IngestionListItem].terminalStatuses.contains(normalizedStatus) &&
            normalizedStatus != "paused"
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
        ingestionStatusLabel(for: item.job) ?? "Processing"
    }

    private var statusDetail: String? {
        ingestionStatusDetail(for: item.job, statusLabel: statusLabel)
    }

    private var metadataText: String {
        guard let detail = statusDetail else { return statusLabel }
        return "\(statusLabel) • \(detail)"
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
}

private struct IngestionCenterActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(.caption)
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: DesignTokens.Animation.quick), value: configuration.isPressed)
    }
}
