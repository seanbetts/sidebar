import Foundation
import UniformTypeIdentifiers

extension IngestionViewModel {
    func mimeTypeFor(url: URL) -> String {
        IngestionUploadPolicy.mimeType(for: url)
    }

    func uploadValidationMessage(for url: URL, mimeType: String? = nil) -> String? {
        IngestionUploadPolicy.rejectionMessage(for: url, mimeType: mimeType)
    }

    func fileSizeBytes(for url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    func normalizeYouTubeUrlCandidate(_ raw: String) -> String? {
        YouTubeURLPolicy.normalizedCandidate(raw)
    }

    func isYouTubeHost(_ rawHost: String) -> Bool {
        YouTubeURLPolicy.isYouTubeHost(rawHost)
    }

    func isValidYouTubeVideoId(_ rawValue: String) -> Bool {
        YouTubeURLPolicy.isValidVideoId(rawValue)
    }

    func releaseSecurityScopedAccess(for fileId: String) {
        guard let url = securityScopedURLs.removeValue(forKey: fileId) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    func makeBookmarkData(for url: URL) -> Data? {
        #if os(macOS)
        if let scoped = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return scoped
        }
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #else
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #endif
        return try? url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) -> URL? {
        #if os(macOS)
        var scopedIsStale = false
        if let scoped = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &scopedIsStale
        ) {
            return scoped
        }
        #endif

        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    func makeFilename(base: String, mimeType: String, fallback: String) -> String {
        if base.contains(".") {
            return base
        }
        if let ext = filenameExtension(for: mimeType) {
            return "\(base).\(ext)"
        }
        return "\(base)-\(fallback)"
    }

    func filenameExtension(for mimeType: String) -> String? {
        let normalized = mimeType.lowercased()
        switch normalized {
        case "application/pdf":
            return "pdf"
        case "application/json":
            return "json"
        case "text/markdown":
            return "md"
        case "text/plain":
            return "txt"
        case "text/csv":
            return "csv"
        case "text/tab-separated-values":
            return "tsv"
        default:
            if normalized.hasPrefix("image/") {
                return normalized.replacingOccurrences(of: "image/", with: "")
            }
            if normalized.hasPrefix("audio/") {
                return normalized.replacingOccurrences(of: "audio/", with: "")
            }
            if normalized.hasPrefix("video/") {
                return normalized.replacingOccurrences(of: "video/", with: "")
            }
            return nil
        }
    }

    func overrideKindIfMarkdown(
        inferredKind: FileViewerKind,
        filename: String,
        mimeType: String
    ) -> FileViewerKind {
        if inferredKind == .text {
            let lower = filename.lowercased()
            if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
                return .markdown
            }
            if mimeType.lowercased() == "text/markdown" {
                return .markdown
            }
        }
        return inferredKind
    }
}
