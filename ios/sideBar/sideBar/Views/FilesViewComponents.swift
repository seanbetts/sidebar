import SwiftUI
import UniformTypeIdentifiers

struct PdfHeaderControls: View {
    @ObservedObject var controller: PDFViewerController
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            PdfControlButton(
                systemName: "chevron.left",
                accessibilityLabel: "Previous page",
                isDisabled: !controller.canPrev
            ) {
                controller.goToPreviousPage()
            }
            Text(pageLabel)
                .font(isCompact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: isCompact ? 44 : 60)
            PdfControlButton(
                systemName: "chevron.right",
                accessibilityLabel: "Next page",
                isDisabled: !controller.canNext
            ) {
                controller.goToNextPage()
            }
            PdfControlButton(
                systemName: "minus",
                accessibilityLabel: "Zoom out"
            ) {
                controller.zoomOut()
            }
            PdfControlButton(
                systemName: "plus",
                accessibilityLabel: "Zoom in"
            ) {
                controller.zoomIn()
            }
            Text(zoomLabel)
                .font(isCompact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: isCompact ? 44 : 56)
            PdfControlButton(
                systemName: "distribute.vertical",
                accessibilityLabel: "Fit to height",
                isActive: false
            ) {
                controller.setFitMode(.height)
            }
            PdfControlButton(
                systemName: "distribute.horizontal",
                accessibilityLabel: "Fit to width",
                isActive: false
            ) {
                controller.setFitMode(.width)
            }
        }
    }

    private var pageLabel: String {
        "\(controller.currentPage) / \(max(controller.pageCount, 1))"
    }

    private var zoomLabel: String {
        let percent = Int(round(controller.zoomMultiplier * 100))
        return "\(percent)%"
    }
}

struct PdfControlButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 20)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
    }
}

struct BinaryFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct FilesDetailContainer: View {
    @ObservedObject var viewModel: IngestionViewModel
    @ObservedObject var pdfController: PDFViewerController

    var body: some View {
        if let meta = viewModel.activeMeta {
            IngestionDetailView(viewModel: viewModel, meta: meta, pdfController: pdfController)
        } else if let selectedItem = viewModel.selectedItem,
                  viewModel.selectedFileId != nil,
                  viewModel.errorMessage == nil,
                  !viewModel.isSelecting,
                  !viewModel.isLoadingContent,
                  shouldShowProcessingState(for: selectedItem) {
            FilesProcessingView(item: selectedItem)
        } else if let message = viewModel.errorMessage {
            PlaceholderView(
                title: "Unable to load file",
                subtitle: message,
                actionTitle: viewModel.selectedFileId == nil ? nil : "Retry"
            ) {
                guard let selectedId = viewModel.selectedFileId else { return }
                Task { await viewModel.selectFile(fileId: selectedId) }
            }
        } else if viewModel.isSelecting || viewModel.selectedFileId != nil {
            LoadingView(message: "Loading file…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            LoadingView(message: "Loading files…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlaceholderView(
                title: "Select a file",
                subtitle: "Choose a file from the sidebar.",
                iconName: "folder"
            )
        }
    }

    private func shouldShowProcessingState(for item: IngestionListItem) -> Bool {
        let status = item.statusValue
        return !Array<IngestionListItem>.terminalStatuses.contains(status)
    }
}

struct FilesProcessingView: View {
    let item: IngestionListItem

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.1)
            if let progress = item.job.progress {
                ProgressView(value: progress)
            }
            Text(statusTitle)
                .font(.headline)
            if let detail = statusDetail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusTitle: String {
        if (item.job.status ?? "") == "uploading" {
            return "Uploading file…"
        }
        return "Processing file…"
    }

    private var statusDetail: String? {
        if let message = item.job.userMessage, !message.isEmpty {
            return message
        }
        return ingestionStatusLabel(for: item.job)
    }
}
