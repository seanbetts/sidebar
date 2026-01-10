import Foundation

public enum FileViewerKind: String {
    case pdf
    case image
    case video
    case audio
    case markdown
    case text
    case json
    case spreadsheet
    case quickLook

    public static func infer(path: String?, mimeType: String?, derivativeKind: String?) -> FileViewerKind {
        if let derivativeKind {
            switch derivativeKind {
            case "viewer_pdf":
                return .pdf
            case "viewer_json":
                return .spreadsheet
            case "ai_md":
                return .markdown
            case "text_original":
                return .text
            case "image_original":
                return .image
            case "audio_original":
                return .audio
            case "video_original", "viewer_video":
                return .video
            default:
                break
            }
        }

        if let mimeType {
            let normalized = mimeType.lowercased()
            if normalized == "application/pdf" {
                return .pdf
            }
            if normalized.hasPrefix("image/") {
                return .image
            }
            if normalized.hasPrefix("audio/") {
                return .audio
            }
            if normalized.hasPrefix("video/") {
                return .video
            }
            if normalized == "text/markdown" {
                return .markdown
            }
            if normalized == "application/json" || normalized.contains("json") {
                return .json
            }
            if normalized.hasPrefix("text/") {
                return .text
            }
        }

        if let path {
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            switch ext {
            case "md", "markdown":
                return .markdown
            case "pdf":
                return .pdf
            case "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff":
                return .image
            case "mp3", "m4a", "wav", "aac", "ogg", "flac":
                return .audio
            case "mp4", "mov", "m4v", "webm":
                return .video
            case "json":
                return .json
            case "csv", "tsv", "xls", "xlsx", "xlsm":
                return .spreadsheet
            case "txt", "log", "yml", "yaml":
                return .text
            default:
                break
            }
        }

        return .quickLook
    }
}

public struct FileViewerState {
    public let title: String
    public let kind: FileViewerKind
    public let text: String?
    public let fileURL: URL?
    public let spreadsheet: SpreadsheetPayload?

    public init(
        title: String,
        kind: FileViewerKind,
        text: String?,
        fileURL: URL?,
        spreadsheet: SpreadsheetPayload?
    ) {
        self.title = title
        self.kind = kind
        self.text = text
        self.fileURL = fileURL
        self.spreadsheet = spreadsheet
    }
}
