import SwiftUI

public struct FilesView: View {
    @EnvironmentObject private var environment: AppEnvironment

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
        FilesDetailContainer(viewModel: environment.ingestionViewModel)
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
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button {
            } label: {
                Image(systemName: "line.3.horizontal")
            }
            .buttonStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .imageScale(.medium)
            .accessibilityLabel("File options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
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
