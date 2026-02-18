import SwiftUI

public struct IngestionDetailView: View {
    @ObservedObject var viewModel: IngestionViewModel
    let meta: IngestionMetaResponse
    let pdfController: PDFViewerController

    public init(viewModel: IngestionViewModel, meta: IngestionMetaResponse, pdfController: PDFViewerController) {
        self.viewModel = viewModel
        self.meta = meta
        self.pdfController = pdfController
    }

    public var body: some View {
        VStack(spacing: 12) {
            viewer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var viewer: some View {
        Group {
            if viewModel.isSelecting || viewModel.isLoadingContent {
                LoadingView(message: "Loading file…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shouldShowProcessingState {
                VStack(spacing: 16) {
                    LoadingIndicatorView(size: LoadingIndicatorSize.page)
                    PlaceholderView(
                        title: "Processing file…",
                        subtitle: processingDetail
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let state = viewModel.viewerState {
                FileViewerView(state: state, pdfController: pdfController)
            } else if let error = viewModel.errorMessage {
                PlaceholderView(
                    title: "Unable to load preview",
                    subtitle: error,
                    actionTitle: "Retry"
                ) {
                    Task {
                        if let kind = viewModel.selectedDerivativeKind {
                            await viewModel.selectDerivative(kind: kind)
                        } else {
                            await viewModel.loadMeta(fileId: meta.file.id)
                        }
                    }
                }
            } else {
                PlaceholderView(title: "Preview unavailable")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldShowProcessingState: Bool {
        Self.shouldShowProcessingState(status: meta.job.status, errorMessage: viewModel.errorMessage)
    }

    static func shouldShowProcessingState(status: String?, errorMessage: String?) -> Bool {
        if let errorMessage, !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        let normalizedStatus = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedStatus != "ready" && normalizedStatus != "failed" && normalizedStatus != "canceled"
    }

    private var processingDetail: String? {
        if let message = meta.job.userMessage, !message.isEmpty {
            return message
        }
        return ingestionStatusLabel(for: meta.job) ?? "We will open this file once processing completes."
    }

}
