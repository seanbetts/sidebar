import SwiftUI
import UniformTypeIdentifiers

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
            if isCompact, hasActiveSelection {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    FilesHeaderActions(viewModel: environment.ingestionViewModel)
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

    private var hasActiveSelection: Bool {
        environment.ingestionViewModel.selectedFileId != nil
    }
}

private struct FilesHeaderView: View {
    @ObservedObject var viewModel: IngestionViewModel

    var body: some View {
        ContentHeaderRow(
            iconName: iconName,
            title: activeTitle,
            subtitle: activeFileType,
            titleLineLimit: 1,
            subtitleLineLimit: 1,
            titleLayoutPriority: 0,
            subtitleLayoutPriority: 1,
            subtitleShowsDivider: activeFileType != nil,
            subtitleDividerWidth: 2,
            subtitleDividerHeight: 28,
            subtitleTracking: 0.8
        ) {
            if viewModel.selectedFileId != nil {
                FilesHeaderActions(viewModel: viewModel)
            }
        }
        .padding(16)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    private var activeTitle: String {
        if let name = selectedFilenameOriginal {
            return stripFileExtension(name)
        }
        return "Files"
    }

    private var activeFileType: String? {
        guard let name = selectedFilenameOriginal else { return nil }
        return fileTypeLabel(name: name, mime: selectedMimeOriginal)
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

    private var selectedMimeOriginal: String? {
        if let mime = viewModel.activeMeta?.file.mimeOriginal {
            return mime
        }
        guard let selectedId = viewModel.selectedFileId else {
            return nil
        }
        return viewModel.items.first { $0.file.id == selectedId }?.file.mimeOriginal
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

    private func fileTypeLabel(name: String, mime: String?) -> String {
        guard let mime else {
            return extensionLabel(from: name)
        }
        let normalized = mime.split(separator: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? mime
        let pretty: [String: String] = [
            "application/pdf": "PDF",
            "application/vnd.ms-excel": "XLS",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "DOCX",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "XLSX",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation": "PPTX",
            "application/msword": "DOC",
            "application/vnd.ms-powerpoint": "PPT",
            "application/rtf": "RTF",
            "text/csv": "CSV",
            "application/csv": "CSV",
            "text/tab-separated-values": "TSV",
            "text/tsv": "TSV",
            "text/plain": "TXT",
            "text/markdown": "MD",
            "text/html": "HTML",
            "application/json": "JSON",
            "text/xml": "XML",
            "application/xml": "XML",
            "text/javascript": "JS",
            "application/javascript": "JS",
            "text/css": "CSS",
            "application/zip": "ZIP",
            "application/x-zip-compressed": "ZIP",
            "application/gzip": "GZIP",
            "application/epub+zip": "EPUB",
            "application/vnd.oasis.opendocument.text": "ODT",
            "application/vnd.oasis.opendocument.spreadsheet": "ODS"
        ]
        if normalized.hasPrefix("image/") {
            return normalized.split(separator: "/").last.map { String($0).uppercased() } ?? "IMAGE"
        }
        if normalized.hasPrefix("audio/") {
            let subtype = normalized.split(separator: "/").last.map { String($0) } ?? "audio"
            let audioPretty: [String: String] = [
                "mpeg": "MP3",
                "mp3": "MP3",
                "x-m4a": "M4A",
                "m4a": "M4A",
                "x-wav": "WAV",
                "wav": "WAV",
                "flac": "FLAC",
                "ogg": "OGG"
            ]
            return audioPretty[subtype] ?? subtype.replacingOccurrences(of: "x-", with: "").uppercased()
        }
        if normalized == "video/youtube" {
            return "YouTube"
        }
        if normalized.hasPrefix("video/") {
            let subtype = normalized.split(separator: "/").last.map { String($0) } ?? "video"
            return subtype.replacingOccurrences(of: "x-", with: "").uppercased()
        }
        if normalized == "application/octet-stream" {
            return extensionLabel(from: name)
        }
        return pretty[normalized] ?? mime
    }

    private func extensionLabel(from name: String) -> String {
        guard let extensionMatch = name.range(of: "\\.[^./]+$", options: .regularExpression) else {
            return "FILE"
        }
        return name[extensionMatch].dropFirst().uppercased()
    }
}

private struct FilesHeaderActions: View {
    @ObservedObject var viewModel: IngestionViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isRenameSheetPresented = false
    @State private var renameValue: String = ""
    @State private var isDeleteAlertPresented = false
    @State private var exportDocument: BinaryFileDocument?
    @State private var isExporting = false
    @State private var exportFilename: String = "file"

    var body: some View {
        HeaderActionRow {
            fileActionsMenu
            closeButton
        }
        .alert(deleteDialogTitle, isPresented: $isDeleteAlertPresented) {
            Button("Delete", role: .destructive) {
                Task { await deleteActiveFile() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the file and cannot be undone.")
        }
        .sheet(isPresented: $isRenameSheetPresented) {
            RenameItemSheet(
                title: "Rename File",
                placeholder: "File name",
                text: $renameValue
            ) { newName in
                Task { await renameFile(to: newName) }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .data,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
    }

    private var fileActionsMenu: some View {
        #if os(macOS)
        Menu {
            Button {
                Task { await togglePin() }
            } label: {
                Label(pinActionTitle, systemImage: pinIconName)
            }
            Button {
                beginRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                copyFileContent()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                Task { await downloadFile() }
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
            Button(role: .destructive) {
                isDeleteAlertPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            HeaderActionIcon(systemName: "ellipsis.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("File options")
        .disabled(viewModel.selectedFileId == nil)
        #else
        UIKitMenuButton(
            systemImage: "ellipsis.circle",
            accessibilityLabel: "File options",
            items: [
                MenuActionItem(title: pinActionTitle, systemImage: pinIconName, role: nil) {
                    Task { await togglePin() }
                },
                MenuActionItem(title: "Rename", systemImage: "pencil", role: nil) {
                    beginRename()
                },
                MenuActionItem(title: "Copy", systemImage: "doc.on.doc", role: nil) {
                    copyFileContent()
                },
                MenuActionItem(title: "Download", systemImage: "square.and.arrow.down", role: nil) {
                    Task { await downloadFile() }
                },
                MenuActionItem(title: "Delete", systemImage: "trash", role: .destructive) {
                    isDeleteAlertPresented = true
                }
            ]
        )
        .frame(width: 28, height: 20)
        .accessibilityLabel("File options")
        .disabled(viewModel.selectedFileId == nil)
        #endif
    }

    private var closeButton: some View {
        HeaderActionButton(
            systemName: "xmark",
            accessibilityLabel: "Close file",
            action: {
                viewModel.clearSelection()
            },
            isDisabled: viewModel.selectedFileId == nil
        )
    }

    private var pinActionTitle: String {
        isPinned ? "Unpin" : "Pin"
    }

    private var pinIconName: String {
        isPinned ? "pin.slash" : "pin"
    }

    private var isPinned: Bool {
        if let meta = viewModel.activeMeta {
            return meta.file.pinned ?? false
        }
        guard let selectedId = viewModel.selectedFileId else { return false }
        return viewModel.items.first { $0.file.id == selectedId }?.file.pinned ?? false
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

    private var deleteDialogTitle: String {
        guard let name = selectedFilenameOriginal else {
            return "Delete file"
        }
        return "Delete \"\(stripFileExtension(name))\"?"
    }

    private func togglePin() async {
        guard let selectedId = viewModel.selectedFileId else { return }
        await viewModel.togglePinned(fileId: selectedId, pinned: !isPinned)
    }

    private func beginRename() {
        guard let name = selectedFilenameOriginal else { return }
        renameValue = stripFileExtension(name)
        isRenameSheetPresented = true
    }

    private func renameFile(to newName: String) async {
        guard let selectedId = viewModel.selectedFileId else { return }
        let originalName = selectedFilenameOriginal ?? newName
        let updatedName = applyFileExtension(originalName: originalName, newName: newName)
        let success = await viewModel.renameFile(fileId: selectedId, filename: updatedName)
        if !success {
            environment.toastCenter.show(message: "Failed to rename file")
        }
    }

    private func copyFileContent() {
        guard let text = viewModel.viewerState?.text, !text.isEmpty else {
            environment.toastCenter.show(message: "Copy unavailable for this file")
            return
        }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func downloadFile() async {
        guard let meta = viewModel.activeMeta else {
            environment.toastCenter.show(message: "Download unavailable")
            return
        }
        let kind = viewModel.selectedDerivativeKind
            ?? meta.recommendedViewer
            ?? meta.derivatives.first?.kind
        guard let kind else {
            environment.toastCenter.show(message: "Download unavailable")
            return
        }
        do {
            let data = try await environment.container.ingestionAPI.getContent(
                fileId: meta.file.id,
                kind: kind,
                range: nil
            )
            exportDocument = BinaryFileDocument(data: data)
            exportFilename = meta.file.filenameOriginal
            isExporting = true
        } catch {
            environment.toastCenter.show(message: "Failed to download file")
        }
    }

    private func deleteActiveFile() async {
        guard let selectedId = viewModel.selectedFileId else { return }
        let success = await viewModel.deleteFile(fileId: selectedId)
        if !success {
            environment.toastCenter.show(message: "Failed to delete file")
        }
    }

    private func applyFileExtension(originalName: String, newName: String) -> String {
        guard let extensionMatch = originalName.range(of: "\\.[^./]+$", options: .regularExpression) else {
            return newName
        }
        let ext = String(originalName[extensionMatch])
        if newName.hasSuffix(ext) {
            return newName
        }
        return newName + ext
    }
}

private struct BinaryFileDocument: FileDocument {
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
