import SwiftUI
import Combine
import UniformTypeIdentifiers

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
            if environment.isOffline {
                OfflineBanner()
            }
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
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if shouldShowPdfControls {
                        PdfHeaderControls(controller: pdfController, isCompact: true)
                    }
                }
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
        return mime.split(separator: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "application/pdf"
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

private struct FilesHeaderView: View {
    @ObservedObject var viewModel: IngestionViewModel
    @ObservedObject var pdfController: PDFViewerController

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
                HeaderActionRow {
                    if isPdf {
                        PdfHeaderControls(controller: pdfController, isCompact: false)
                    }
                    FilesHeaderActions(viewModel: viewModel)
                }
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
            return normalizedFilename(name: name, mime: viewModel.activeMeta?.file.mimeOriginal)
        }
        guard let selectedId = viewModel.selectedFileId else {
            return nil
        }
        if let item = viewModel.items.first(where: { $0.file.id == selectedId }) {
            return normalizedFilename(name: item.file.filenameOriginal, mime: item.file.mimeOriginal)
        }
        return nil
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

    private var isPdf: Bool {
        if let mime = selectedMimeOriginal {
            let normalized = mime.split(separator: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? mime
            if normalized == "application/pdf" {
                return true
            }
        }
        return selectedRecommendedViewer == "viewer_pdf"
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

    private func normalizedFilename(name: String, mime: String?) -> String {
        if mime?.lowercased() == "video/youtube", name.lowercased() == "youtube video" {
            return "YouTube Video"
        }
        return name
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
        .onReceive(environment.$shortcutActionEvent) { event in
            guard let event, event.section == .files else { return }
            switch event.action {
            case .renameItem:
                beginRename()
            case .deleteItem:
                isDeleteAlertPresented = true
            case .openInDefaultApp:
                Task { await downloadFile() }
            case .quickLook:
                environment.toastCenter.show(message: "Quick Look is not available yet")
            default:
                break
            }
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

private struct PdfHeaderControls: View {
    @ObservedObject var controller: PDFViewerController
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            PdfControlButton(
                systemName: "chevron.left",
                accessibilityLabel: "Previous page",
                isDisabled: !controller.canPrev
            ) {
                controller.goToPreviousPage()
            }
            Text(pageLabel)
                .font(isCompact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: isCompact ? 44 : 60)
            PdfControlButton(
                systemName: "chevron.right",
                accessibilityLabel: "Next page",
                isDisabled: !controller.canNext
            ) {
                controller.goToNextPage()
            }
            PdfControlButton(
                systemName: "minus",
                accessibilityLabel: "Zoom out"
            ) {
                controller.zoomOut()
            }
            PdfControlButton(
                systemName: "plus",
                accessibilityLabel: "Zoom in"
            ) {
                controller.zoomIn()
            }
            Text(zoomLabel)
                .font(isCompact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: isCompact ? 44 : 56)
            PdfControlButton(
                systemName: "distribute.vertical",
                accessibilityLabel: "Fit to height",
                isActive: false
            ) {
                controller.setFitMode(.height)
            }
            PdfControlButton(
                systemName: "distribute.horizontal",
                accessibilityLabel: "Fit to width",
                isActive: false
            ) {
                controller.setFitMode(.width)
            }
        }
    }

    private var pageLabel: String {
        "\(controller.currentPage) / \(max(controller.pageCount, 1))"
    }

    private var zoomLabel: String {
        let percent = Int(round(controller.zoomMultiplier * 100))
        return "\(percent)%"
    }
}

private struct PdfControlButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 20)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
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
    @ObservedObject var pdfController: PDFViewerController

    var body: some View {
        if let meta = viewModel.activeMeta {
            IngestionDetailView(viewModel: viewModel, meta: meta, pdfController: pdfController)
        } else if let selectedItem = viewModel.selectedItem,
                  viewModel.selectedFileId != nil,
                  viewModel.errorMessage == nil,
                  !viewModel.isSelecting,
                  !viewModel.isLoadingContent,
                  shouldShowProcessingState(for: selectedItem) {
            FilesProcessingView(item: selectedItem)
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
                subtitle: "Choose a file from the sidebar.",
                iconName: "folder"
            )
        }
    }

    private func shouldShowProcessingState(for item: IngestionListItem) -> Bool {
        let status = item.job.status ?? ""
        return status != "ready" && status != "failed" && status != "canceled"
    }
}

private struct FilesProcessingView: View {
    let item: IngestionListItem

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.1)
            if let progress = item.job.progress {
                ProgressView(value: progress)
            }
            Text(statusTitle)
                .font(.headline)
            if let detail = statusDetail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusTitle: String {
        if (item.job.status ?? "") == "uploading" {
            return "Uploading file…"
        }
        return "Processing file…"
    }

    private var statusDetail: String? {
        if let message = item.job.userMessage, !message.isEmpty {
            return message
        }
        return ingestionStatusLabel(for: item.job)
    }
}
