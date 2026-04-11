import SwiftUI
import UniformTypeIdentifiers
import sideBarShared

struct PdfViewerFloatingControls: View {
    @ObservedObject var controller: PDFViewerController

    var body: some View {
        HeaderActionMenuControl(
            systemName: "doc.viewfinder",
            accessibilityLabel: "PDF controls",
            chromeStyle: .glass
        ) {
            Section("Page") {
                Button {
                    controller.goToPreviousPage()
                } label: {
                    Label("Previous page", systemImage: "chevron.left")
                }
                .disabled(!controller.canPrev)

                Button {
                    controller.goToNextPage()
                } label: {
                    Label("Next page", systemImage: "chevron.right")
                }
                .disabled(!controller.canNext)
            }

            Section("Zoom") {
                Button {
                    controller.zoomOut()
                } label: {
                    Label("Zoom out", systemImage: "minus.magnifyingglass")
                }

                Button {
                    controller.zoomIn()
                } label: {
                    Label("Zoom in", systemImage: "plus.magnifyingglass")
                }

                Text("Zoom: \(zoomLabel)")
            }

            Section("Fit") {
                fitModeButton("Fit to height", systemImage: "distribute.vertical", mode: .height)
                fitModeButton("Fit to width", systemImage: "distribute.horizontal", mode: .width)
            }

            Section("Status") {
                Text("Page \(pageLabel)")
            }
        }
        .accessibilityIdentifier("pdf-floating-controls")
    }

    private var pageLabel: String {
        "\(controller.currentPage) / \(max(controller.pageCount, 1))"
    }

    private var zoomLabel: String {
        let percent = Int(round(controller.zoomMultiplier * 100))
        return "\(percent)%"
    }

    @ViewBuilder
    private func fitModeButton(
        _ title: String,
        systemImage: String,
        mode: PDFViewerController.FitMode
    ) -> some View {
        Button {
            controller.setFitMode(mode)
        } label: {
            if controller.fitMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Label(title, systemImage: systemImage)
            }
        }
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
