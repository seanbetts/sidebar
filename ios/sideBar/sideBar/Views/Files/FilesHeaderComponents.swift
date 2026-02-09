import SwiftUI
import sideBarShared
import UniformTypeIdentifiers

struct FilesHeaderView: View {
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
        , trailing: {
            if viewModel.selectedFileId != nil {
                HeaderActionRow {
                    if isPdf {
                        PdfHeaderControls(controller: pdfController, isCompact: false)
                    }
                    FilesHeaderActions(viewModel: viewModel)
                }
            }
        })
        .padding(DesignTokens.Spacing.md)
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
            let normalized = mime.split(separator: ";").first?.trimmed.lowercased() ?? mime
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
        let normalized = mime.split(separator: ";").first?.trimmed.lowercased() ?? mime
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
