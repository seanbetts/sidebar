import Foundation
import sideBarShared

/// Represents RealtimeMappers.
public struct RealtimeMappers {
    public static func mapNote(_ record: NoteRealtimeRecord) -> NotePayload? {
        let id = record.id
        let hasSemanticDocument = record.document != nil
        let resolvedDocument = record.document
            ?? NotesSemanticDocumentProjection.document(fromPlainText: record.plainText ?? "")
        let hasExplicitTitleBlock = resolvedDocument.blocks.first?.type == .title
        let plainText = hasSemanticDocument
            ? NotesSemanticDocumentProjection.plainText(from: resolvedDocument)
            : (record.plainText ?? NotesSemanticDocumentProjection.plainText(from: resolvedDocument))
        let title = hasSemanticDocument && hasExplicitTitleBlock
            ? NotesSemanticDocumentProjection.title(from: resolvedDocument)
            : (record.title ?? NotesSemanticDocumentProjection.title(fromPlainText: plainText))
        // NOTE: Align note mapping with native models and folder/archive semantics.
        return NotePayload(
            id: id,
            name: title,
            document: resolvedDocument,
            documentVersion: record.documentVersion ?? resolvedDocument.version,
            plainText: plainText,
            path: id,
            modified: DateParsing.parseISO8601(record.updatedAt)?.timeIntervalSince1970,
            created: DateParsing.parseISO8601(record.updatedAt)?.timeIntervalSince1970
        )
    }

    public static func mapWebsite(_ record: WebsiteRealtimeRecord) -> WebsiteItem? {
        let id = record.id
        // NOTE: Align website mapping with native list models and pinning rules.
        return WebsiteItem(
            id: id,
            title: record.title ?? "",
            url: record.url ?? "",
            domain: record.domain ?? "",
            savedAt: record.savedAt,
            publishedAt: record.publishedAt,
            pinned: (record.metadata?["pinned"]?.value as? Bool) ?? false,
            pinnedOrder: record.metadata?["pinned_order"]?.value as? Int,
            archived: (record.metadata?["archived"]?.value as? Bool) ?? false,
            faviconUrl: record.metadata?["favicon_url"]?.value as? String,
            faviconR2Key: record.metadata?["favicon_r2_key"]?.value as? String,
            youtubeTranscripts: websiteTranscriptEntries(from: record.metadata?["youtube_transcripts"]?.value),
            readingTime: record.readingTime ?? (record.metadata?["reading_time"]?.value as? String),
            updatedAt: record.updatedAt,
            lastOpenedAt: record.lastOpenedAt,
            deletedAt: record.deletedAt
        )
    }

    public static func mapIngestedFile(_ record: IngestedFileRealtimeRecord) -> IngestedFileMeta? {
        let id = record.id
        // NOTE: Normalize ingestion fields to native viewer model once defined.
        return IngestedFileMeta(
            id: id,
            filenameOriginal: record.filenameOriginal ?? "",
            path: record.path,
            mimeOriginal: record.mimeOriginal ?? "",
            sizeBytes: record.sizeBytes ?? 0,
            sha256: record.sha256,
            pinned: record.pinned,
            pinnedOrder: record.pinnedOrder,
            category: nil,
            sourceUrl: record.sourceUrl,
            sourceMetadata: record.sourceMetadata,
            createdAt: record.createdAt ?? record.updatedAt ?? "",
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt
        )
    }

    public static func mapFileJob(_ record: FileJobRealtimeRecord) -> IngestionJob {
        IngestionJob(
            status: record.status,
            stage: record.stage,
            errorCode: record.errorCode,
            errorMessage: record.errorMessage,
            userMessage: nil,
            progress: nil,
            attempts: record.attempts ?? 0,
            updatedAt: record.updatedAt
        )
    }

    private static func websiteTranscriptEntries(
        from value: Any?
    ) -> [String: WebsiteTranscriptEntry]? {
        guard let dictionary = value as? [String: Any], !dictionary.isEmpty else {
            return nil
        }

        var entries: [String: WebsiteTranscriptEntry] = [:]
        entries.reserveCapacity(dictionary.count)

        for (videoId, rawEntry) in dictionary {
            guard let entryDictionary = rawEntry as? [String: Any] else { continue }
            entries[videoId] = WebsiteTranscriptEntry(
                status: entryDictionary["status"] as? String,
                fileId: entryDictionary["file_id"] as? String,
                updatedAt: entryDictionary["updated_at"] as? String,
                error: entryDictionary["error"] as? String
            )
        }

        return entries.isEmpty ? nil : entries
    }
}
