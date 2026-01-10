import SwiftUI

public struct IngestionDetailView: View {
    @ObservedObject var viewModel: IngestionViewModel
    let meta: IngestionMetaResponse

    public init(viewModel: IngestionViewModel, meta: IngestionMetaResponse) {
        self.viewModel = viewModel
        self.meta = meta
    }

    public var body: some View {
        viewer
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var viewer: some View {
        Group {
            if viewModel.isLoadingContent {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let state = viewModel.viewerState {
                FileViewerView(state: state)
            } else if let error = viewModel.errorMessage {
                PlaceholderView(title: error)
            } else {
                PlaceholderView(title: "Preview unavailable")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
