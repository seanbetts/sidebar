import Foundation
import SwiftUI

struct FilesIngestionRow: View, Equatable {
    let item: IngestionListItem
    let isSelected: Bool
    let onPinToggle: (() -> Void)?
    let onDelete: (() -> Void)?

    init(
        item: IngestionListItem,
        isSelected: Bool,
        onPinToggle: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onPinToggle = onPinToggle
        self.onDelete = onDelete
    }

    static func == (lhs: FilesIngestionRow, rhs: FilesIngestionRow) -> Bool {
        lhs.isSelected == rhs.isSelected &&
        lhs.item.file.id == rhs.item.file.id &&
        lhs.item.file.filenameOriginal == rhs.item.file.filenameOriginal &&
        lhs.item.file.category == rhs.item.file.category &&
        lhs.item.file.pinned == rhs.item.file.pinned &&
        lhs.item.file.pinnedOrder == rhs.item.file.pinnedOrder &&
        lhs.item.job.status == rhs.item.job.status &&
        lhs.item.job.stage == rhs.item.job.stage &&
        lhs.item.job.progress == rhs.item.job.progress &&
        lhs.item.job.errorMessage == rhs.item.job.errorMessage &&
        lhs.item.recommendedViewer == rhs.item.recommendedViewer
    }

    var body: some View {
        SelectableRow(isSelected: isSelected, insets: rowInsets) {
            HStack(spacing: 8) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: iconName)
                        .foregroundStyle(isSelected ? selectedTextColor : secondaryTextColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                    if let statusText {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusTextColor)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onPinToggle {
                let title = (item.file.pinned ?? false) ? "Unpin" : "Pin"
                Button(title) {
                    onPinToggle()
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onDelete {
                Button("Delete") {
                    onDelete()
                }
                .tint(.red)
            }
        }
        #endif
    }

    private var iconName: String {
        if item.file.category == "folder" {
            return folderIconName(for: displayName)
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

    private var statusText: String? {
        let status = item.job.status ?? ""
        if status.isEmpty || status == "ready" {
            return nil
        }
        return ingestionStatusLabel(for: item.job) ?? "Processing"
    }

    private var statusTextColor: Color {
        if isFailed {
            return .orange
        }
        return secondaryTextColor
    }

    private var isProcessing: Bool {
        let status = item.statusValue
        return !status.isEmpty && !Array<IngestionListItem>.terminalStatuses.contains(status)
    }

    private var isFailed: Bool {
        item.statusValue == "failed"
    }

    private var displayName: String {
        let name = stripFileExtension(item.file.filenameOriginal)
        if item.file.mimeOriginal.lowercased() == "video/youtube", name.lowercased() == "youtube video" {
            return "YouTube Video"
        }
        return name
    }

    private func folderIconName(for name: String) -> String {
        switch name.lowercased() {
        case "documents":
            return "doc.text"
        case "images":
            return "photo"
        case "audio":
            return "waveform"
        case "video":
            return "video"
        case "spreadsheets":
            return "tablecells"
        case "presentations":
            return "rectangle.on.rectangle.angled"
        case "reports":
            return "chart.line.text.clipboard"
        default:
            return "folder"
        }
    }

    private var primaryTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private var selectedTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var rowInsets: EdgeInsets {
        let horizontalPadding: CGFloat
        #if os(macOS)
        horizontalPadding = DesignTokens.Spacing.xs
        #else
        horizontalPadding = item.file.category == "folder" ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }
}
