import Foundation
import sideBarShared

struct IngestionDerivativeViewerPayload: Sendable {
    let kind: FileViewerKind
    var text: String?
    let fileURL: URL?
    let spreadsheet: SpreadsheetPayload?

    func viewerState(title: String, youtubeEmbedURL: URL?) -> FileViewerState {
        FileViewerState(
            title: title,
            kind: kind,
            text: text,
            fileURL: fileURL,
            spreadsheet: spreadsheet,
            youtubeEmbedURL: youtubeEmbedURL
        )
    }
}

enum IngestionDerivativeViewerPayloadPreparer {
    nonisolated static func prepare(
        data: Data,
        originalFilename: String,
        mimeType: String,
        derivativeKind: String,
        temporaryStore: TemporaryFileStore
    ) async -> IngestionDerivativeViewerPayload {
        await Task.detached(priority: .userInitiated) {
            prepareSynchronously(
                data: data,
                originalFilename: originalFilename,
                mimeType: mimeType,
                derivativeKind: derivativeKind,
                temporaryStore: temporaryStore
            )
        }.value
    }

    private nonisolated static func prepareSynchronously(
        data: Data,
        originalFilename: String,
        mimeType: String,
        derivativeKind: String,
        temporaryStore: TemporaryFileStore
    ) -> IngestionDerivativeViewerPayload {
        let inferredKind = FileViewerKind.infer(
            path: nil,
            mimeType: mimeType,
            derivativeKind: derivativeKind
        )
        let kind = overrideKindIfMarkdown(
            inferredKind: inferredKind,
            filename: originalFilename,
            mimeType: mimeType
        )
        let filename = makeFilename(
            base: originalFilename,
            mimeType: mimeType,
            fallback: derivativeKind
        )
        let fileURL = try? temporaryStore.store(data: data, filename: filename)

        switch kind {
        case .markdown, .text, .json:
            let rawText = String(bytes: data, encoding: .utf8) ?? ""
            let shouldStrip = derivativeKind == "ai_md" || kind == .markdown
            return IngestionDerivativeViewerPayload(
                kind: kind,
                text: shouldStrip ? MarkdownRendering.stripFrontmatter(rawText) : rawText,
                fileURL: fileURL,
                spreadsheet: nil
            )
        case .spreadsheet:
            return IngestionDerivativeViewerPayload(
                kind: .spreadsheet,
                text: nil,
                fileURL: fileURL,
                spreadsheet: decodeSpreadsheetPayload(from: data)
            )
        default:
            return IngestionDerivativeViewerPayload(
                kind: kind,
                text: nil,
                fileURL: fileURL,
                spreadsheet: nil
            )
        }
    }

    private nonisolated static func decodeSpreadsheetPayload(from data: Data) -> SpreadsheetPayload? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sheetObjects = root["sheets"] as? [[String: Any]] else {
            return nil
        }

        let sheets = sheetObjects.compactMap(decodeSpreadsheetSheet)
        guard sheets.count == sheetObjects.count else {
            return nil
        }
        return SpreadsheetPayload(sheets: sheets)
    }

    private nonisolated static func decodeSpreadsheetSheet(_ object: [String: Any]) -> SpreadsheetSheet? {
        guard let name = object["name"] as? String,
              let rows = object["rows"] as? [[String]] else {
            return nil
        }
        return SpreadsheetSheet(
            name: name,
            rows: rows,
            headerRow: object["header_row"] as? Int
        )
    }

    private nonisolated static func makeFilename(base: String, mimeType: String, fallback: String) -> String {
        if base.contains(".") {
            return base
        }
        if let ext = filenameExtension(for: mimeType) {
            return "\(base).\(ext)"
        }
        return "\(base)-\(fallback)"
    }

    private nonisolated static func filenameExtension(for mimeType: String) -> String? {
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

    private nonisolated static func overrideKindIfMarkdown(
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
