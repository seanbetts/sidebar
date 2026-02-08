import SwiftUI
import sideBarShared
import Combine
import UniformTypeIdentifiers

// MARK: - FilesView

public struct FilesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @StateObject private var pdfController = PDFViewerController()

    public init() {
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !isCompact {
                FilesHeaderView(
                    viewModel: environment.ingestionViewModel,
                    pdfController: pdfController
                )
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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if hasActiveSelection {
                        FilesHeaderActions(viewModel: environment.ingestionViewModel)
                    }
                }
            }
        }
        #endif
        .onChange(of: environment.ingestionViewModel.selectedFileId) { _, _ in
            pdfController.reset()
        }
    }

    @ViewBuilder
    private var content: some View {
        FilesDetailContainer(viewModel: environment.ingestionViewModel, pdfController: pdfController)
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
            return normalizedFilename(name: name, mime: environment.ingestionViewModel.activeMeta?.file.mimeOriginal)
        }
        guard let selectedId = environment.ingestionViewModel.selectedFileId else {
            return nil
        }
        if let item = environment.ingestionViewModel.items.first(where: { $0.file.id == selectedId }) {
            return normalizedFilename(name: item.file.filenameOriginal, mime: item.file.mimeOriginal)
        }
        return nil
    }

    private func normalizedFilename(name: String, mime: String?) -> String {
        if mime?.lowercased() == "video/youtube", name.lowercased() == "youtube video" {
            return "YouTube Video"
        }
        return name
    }

    private var hasActiveSelection: Bool {
        environment.ingestionViewModel.selectedFileId != nil
    }

    private var shouldShowPdfControls: Bool {
        guard let mime = selectedMimeOriginal else { return false }
        return mime.split(separator: ";").first?.trimmed.lowercased() == "application/pdf"
    }

    private var selectedMimeOriginal: String? {
        if let mime = environment.ingestionViewModel.activeMeta?.file.mimeOriginal {
            return mime
        }
        guard let selectedId = environment.ingestionViewModel.selectedFileId else {
            return nil
        }
        return environment.ingestionViewModel.items.first { $0.file.id == selectedId }?.file.mimeOriginal
    }
}
