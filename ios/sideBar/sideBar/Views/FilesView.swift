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
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Text(activeTitle)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 17)
    }

    private var activeTitle: String {
        if let name = viewModel.activeMeta?.file.filenameOriginal {
            return stripFileExtension(name)
        }
        return "Files"
    }

    private var iconName: String {
        guard let viewer = viewModel.activeMeta?.recommendedViewer else {
            return "folder"
        }
        switch viewer {
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
        case "text_original", "ai_md":
            return "doc.text"
        default:
            return "doc"
        }
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
