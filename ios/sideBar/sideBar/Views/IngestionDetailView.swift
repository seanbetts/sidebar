import SwiftUI

public struct IngestionDetailView: View {
    @ObservedObject var viewModel: IngestionViewModel
    let meta: IngestionMetaResponse

    public init(viewModel: IngestionViewModel, meta: IngestionMetaResponse) {
        self.viewModel = viewModel
        self.meta = meta
    }

    public var body: some View {
        VStack(spacing: 12) {
            if viewModel.isOffline {
                OfflineBanner()
            }
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
                PlaceholderView(
                    title: "Processing file…",
                    subtitle: processingDetail
                )
                .overlay(
                    ProgressView()
                        .scaleEffect(1.1)
                )
            } else if let state = viewModel.viewerState {
                FileViewerView(state: state)
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
        let status = meta.job.status ?? ""
        return status != "ready" && status != "failed" && status != "canceled"
    }

    private var processingDetail: String? {
        if let message = meta.job.userMessage, !message.isEmpty {
            return message
        }
        return ingestionStatusLabel(for: meta.job) ?? "We will open this file once processing completes."
    }

}
