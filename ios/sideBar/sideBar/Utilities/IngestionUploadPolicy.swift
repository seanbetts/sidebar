import Foundation
import UniformTypeIdentifiers

enum IngestionUploadPolicy {
    private static let blockedExtensions: Set<String> = [
        ".plist"
    ]
    private static let allowedMimePrefixes = ["image/", "audio/", "text/", "video/"]
    private static let allowedExactMimes: Set<String> = [
        "application/pdf",
        "application/json",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-excel",
        "text/csv",
        "application/csv",
        "text/tab-separated-values",
        "text/tsv"
    ]
    private static let allowedOctetExtensions: Set<String> = [
        ".pdf",
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".webp",
        ".bmp",
        ".tiff",
        ".tif",
        ".mp3",
        ".wav",
        ".m4a",
        ".aac",
        ".flac",
        ".ogg",
        ".opus",
        ".mp4",
        ".mov",
        ".mkv",
        ".webm",
        ".txt",
        ".md",
        ".markdown",
        ".csv",
        ".tsv",
        ".json",
        ".yml",
        ".yaml",
        ".log",
        ".docx",
        ".pptx",
        ".xlsx",
        ".xls",
        ".xlsm",
        ".xltx",
        ".xltm"
    ]
    private static let supportedPickerExtensions = [
        "pdf",
        "png",
        "jpg",
        "jpeg",
        "gif",
        "webp",
        "bmp",
        "tiff",
        "tif",
        "mp3",
        "wav",
        "m4a",
        "aac",
        "flac",
        "ogg",
        "opus",
        "mp4",
        "mov",
        "mkv",
        "webm",
        "txt",
        "md",
        "markdown",
        "csv",
        "tsv",
        "json",
        "yml",
        "yaml",
        "log",
        "docx",
        "pptx",
        "xlsx",
        "xls",
        "xlsm",
        "xltx",
        "xltm"
    ]

    static let supportedContentTypes: [UTType] = {
        var seen = Set<String>()
        let baseTypes: [UTType] = [
            .pdf,
            .image,
            .audio,
            .movie,
            .plainText,
            .json
        ]
        let extensionTypes = supportedPickerExtensions.compactMap { extensionName in
            UTType(filenameExtension: extensionName)
        }
        return (baseTypes + extensionTypes).filter { type in
            seen.insert(type.identifier).inserted
        }
    }()

    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    static func rejectionMessage(for url: URL, mimeType: String? = nil) -> String? {
        let normalizedExtension = normalizedExtension(for: url.pathExtension)
        if blockedExtensions.contains(normalizedExtension) {
            return "That file type isn't supported yet."
        }
        let resolvedMimeType = (mimeType ?? self.mimeType(for: url))
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "application/octet-stream"
        if isAllowed(mimeType: resolvedMimeType, fileExtension: normalizedExtension) {
            return nil
        }
        return "That file type isn't supported yet."
    }

    static func isAllowed(mimeType: String, fileExtension: String) -> Bool {
        if blockedExtensions.contains(fileExtension) {
            return false
        }
        if allowedMimePrefixes.contains(where: mimeType.hasPrefix) {
            return true
        }
        if allowedExactMimes.contains(mimeType) {
            return true
        }
        if mimeType == "application/octet-stream" {
            return allowedOctetExtensions.contains(fileExtension)
        }
        return false
    }

    private static func normalizedExtension(for pathExtension: String) -> String {
        pathExtension.isEmpty ? "" : ".\(pathExtension.lowercased())"
    }
}
