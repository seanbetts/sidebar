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

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline - showing cached data")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }
}
