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
            if environment.isOffline {
                OfflineBanner()
            }
            if !isCompact {
                FilesHeaderView(viewModel: environment.ingestionViewModel)
                Divider()
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if !os(macOS)
        .navigationTitle(fileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isCompact {
                ToolbarItem(placement: .navigationBarTrailing) {
                        HeaderActionButton(
                            systemName: "ellipsis.circle",
                            accessibilityLabel: "File options",
                            action: {}
                        )
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        FilesDetailContainer(viewModel: environment.ingestionViewModel)
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var fileTitle: String {
        #if os(macOS)
        return "Files"
        #else
        guard horizontalSizeClass == .compact else {
            return "Files"
        }
        guard let name = selectedFilenameOriginal else {
            return "Files"
        }
        return stripFileExtension(name)
        #endif
    }

    private var selectedFilenameOriginal: String? {
        if let name = environment.ingestionViewModel.activeMeta?.file.filenameOriginal {
            return name
        }
        guard let selectedId = environment.ingestionViewModel.selectedFileId else {
            return nil
        }
        return environment.ingestionViewModel.items.first { $0.file.id == selectedId }?.file.filenameOriginal
    }
}

private struct FilesHeaderView: View {
    @ObservedObject var viewModel: IngestionViewModel

    var body: some View {
        ContentHeaderRow(
            iconName: iconName,
            title: activeTitle
        ) {
            HeaderActionButton(
                systemName: "ellipsis.circle",
                accessibilityLabel: "File options",
                action: {}
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var activeTitle: String {
        if let name = selectedFilenameOriginal {
            return stripFileExtension(name)
        }
        return "Files"
    }

    private var iconName: String {
        if selectedCategory == "reports" {
            return "chart.line.text.clipboard"
        }
        if selectedCategory == "presentations" {
            return "rectangle.on.rectangle.angled"
        }
        guard let viewer = selectedRecommendedViewer else {
            return "folder"
        }
        switch viewer {
        case "viewer_pdf":
            return "doc.richtext"
        case "viewer_json":
            return "tablecells"
        case "viewer_video":
            return "video"
        case "viewer_presentation":
            return "rectangle.on.rectangle.angled"
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

    private var selectedFilenameOriginal: String? {
        if let name = viewModel.activeMeta?.file.filenameOriginal {
            return name
        }
        guard let selectedId = viewModel.selectedFileId else {
            return nil
        }
        return viewModel.items.first { $0.file.id == selectedId }?.file.filenameOriginal
    }

    private var selectedCategory: String? {
        if let category = viewModel.activeMeta?.file.category {
            return category
        }
        guard let selectedId = viewModel.selectedFileId else {
            return nil
        }
        return viewModel.items.first { $0.file.id == selectedId }?.file.category
    }

    private var selectedRecommendedViewer: String? {
        if let viewer = viewModel.activeMeta?.recommendedViewer {
            return viewer
        }
        guard let selectedId = viewModel.selectedFileId else {
            return nil
        }
        return viewModel.items.first { $0.file.id == selectedId }?.recommendedViewer
    }
}

private struct FilesDetailContainer: View {
    @ObservedObject var viewModel: IngestionViewModel

    var body: some View {
        if let meta = viewModel.activeMeta {
            IngestionDetailView(viewModel: viewModel, meta: meta)
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
                subtitle: "Choose a file from the sidebar to preview it.",
                iconName: "folder"
            )
        }
    }
}
