import SwiftUI
import UniformTypeIdentifiers
import sideBarShared

struct PdfViewerFloatingControls: View {
    @ObservedObject var controller: PDFViewerController

    var body: some View {
        let configuration = controller.controlBarConfiguration
        Group {
#if os(iOS)
            if #available(iOS 26.0, *) {
                UIKitPDFControlBarRepresentable(
                    configuration: configuration,
                    showsVisibleChrome: true
                )
                .disabled(!configuration.isEnabled)
            } else {
                PDFControlBar(configuration: configuration)
            }
#elseif os(macOS)
            if #available(macOS 26.0, *) {
                AppKitPDFControlOverlay(
                    configuration: configuration,
                    showsVisibleChrome: true
                )
                .disabled(!configuration.isEnabled)
            } else {
                PDFControlBar(configuration: configuration)
            }
#else
            PDFControlBar(configuration: configuration)
#endif
        }
        .accessibilityIdentifier("pdf-floating-controls")
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
                  FilesWorkspaceDisplayPolicy.shouldShowProcessingStateInMainWorkspace(for: selectedItem) {
            FilesProcessingView(item: selectedItem)
        } else if viewModel.selectedFileId != nil,
                  !canAttemptServerRead,
                  viewModel.isSelectedPreviewUnavailableOffline {
            DetailOfflineUnavailablePlaceholder(resource: .file)
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
            WelcomeEmptyView()
        }
    }

    private var canAttemptServerRead: Bool {
        viewModel.networkStatus?.offlineCapabilityPolicy.canAttemptServerRead ?? true
    }

}

struct FilesProcessingView: View {
    let item: IngestionListItem

    var body: some View {
        VStack(spacing: 12) {
            LoadingIndicatorView(size: LoadingIndicatorSize.page)
            if FilesWorkspaceDisplayPolicy.shouldShowUploadProgressInMainWorkspace(for: item),
               let progress = item.job.progress {
                ProgressView(value: progress)
            }
            Text(statusTitle)
                .appFont(.headline)
            if let detail = statusDetail {
                Text(detail)
                    .appFont(.subheadline)
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

enum FilesWorkspaceDisplayPolicy {
    static func shouldShowProcessingStateInMainWorkspace(for item: IngestionListItem) -> Bool {
        let status = item.statusValue
        return ![IngestionListItem].terminalStatuses.contains(status)
    }

    static func shouldShowUploadProgressInMainWorkspace(for _: IngestionListItem) -> Bool {
        false
    }
}
