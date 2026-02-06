import Foundation
import sideBarShared

/// Represents RealtimeMappers.
public struct RealtimeMappers {
    public static func mapNote(_ record: NoteRealtimeRecord) -> NotePayload? {
        let id = record.id
        // NOTE: Align note mapping with native models and folder/archive semantics.
        return NotePayload(
            id: id,
            name: "\(record.title ?? "Untitled").md",
            content: record.content ?? "",
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
            youtubeTranscripts: nil,
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
}
