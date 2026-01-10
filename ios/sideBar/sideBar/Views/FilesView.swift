import SwiftUI

public struct FilesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
    }

    public var body: some View {
        VStack(spacing: 0) {
            FilesHeaderView(viewModel: environment.ingestionViewModel)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        FilesDetailContainer(viewModel: environment.ingestionViewModel)
        #else
        if horizontalSizeClass == .compact {
            IngestionSplitView(viewModel: environment.ingestionViewModel)
        } else {
            FilesDetailContainer(viewModel: environment.ingestionViewModel)
        }
        #endif
    }
}

private struct FilesHeaderView: View {
    @ObservedObject var viewModel: IngestionViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(activeTitle)
                .font(.headline)
            Spacer()
        }
        .padding(16)
    }

    private var activeTitle: String {
        viewModel.activeMeta?.file.filenameOriginal ?? "Files"
    }
}

private struct FilesDetailContainer: View {
    @ObservedObject var viewModel: IngestionViewModel

    var body: some View {
        if let meta = viewModel.activeMeta {
            IngestionDetailView(viewModel: viewModel, meta: meta)
        } else if let message = viewModel.errorMessage {
            PlaceholderView(title: message)
        } else if viewModel.isLoadingContent {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlaceholderView(title: "Select a file")
        }
    }
}
