import Foundation
import Combine
import sideBarShared

/// Represents a website item struct.
public struct WebsiteItem: Codable, Identifiable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The url value.
    public let url: String
    /// The domain value.
    public let domain: String
    /// The saved at value.
    public let savedAt: String?
    /// The published at value.
    public let publishedAt: String?
    /// The pinned value.
    public let pinned: Bool
    /// The pinned order value.
    public let pinnedOrder: Int?
    /// The archived value.
    public let archived: Bool
    /// The favicon url value.
    public let faviconUrl: String?
    /// The favicon r2 key value.
    public let faviconR2Key: String?
    /// The youtube transcripts value.
    public let youtubeTranscripts: [String: WebsiteTranscriptEntry]?
    /// The reading time value.
    public let readingTime: String?
    /// The updated at value.
    public let updatedAt: String?
    /// The last opened at value.
    public let lastOpenedAt: String?
    /// The deleted at value.
    public let deletedAt: String?

    public init(
        id: String,
        title: String,
        url: String,
        domain: String,
        savedAt: String?,
        publishedAt: String?,
        pinned: Bool,
        pinnedOrder: Int?,
        archived: Bool,
        faviconUrl: String?,
        faviconR2Key: String?,
        youtubeTranscripts: [String: WebsiteTranscriptEntry]?,
        readingTime: String?,
        updatedAt: String?,
        lastOpenedAt: String?,
        deletedAt: String?
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.domain = domain
        self.savedAt = savedAt
        self.publishedAt = publishedAt
        self.pinned = pinned
        self.pinnedOrder = pinnedOrder
        self.archived = archived
        self.faviconUrl = faviconUrl
        self.faviconR2Key = faviconR2Key
        self.youtubeTranscripts = youtubeTranscripts
        self.readingTime = readingTime
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.deletedAt = deletedAt
    }

    public init(detail: WebsiteDetail) {
        self.init(
            id: detail.id,
            title: detail.title,
            url: detail.url,
            domain: detail.domain,
            savedAt: detail.savedAt,
            publishedAt: detail.publishedAt,
            pinned: detail.pinned,
            pinnedOrder: detail.pinnedOrder,
            archived: detail.archived,
            faviconUrl: detail.faviconUrl,
            faviconR2Key: detail.faviconR2Key,
            youtubeTranscripts: detail.youtubeTranscripts,
            readingTime: detail.readingTime,
            updatedAt: detail.updatedAt,
            lastOpenedAt: detail.lastOpenedAt,
            deletedAt: nil
        )
    }
}

/// Represents a websites response struct.
public struct WebsitesResponse: Codable {
    /// The items value.
    public let items: [WebsiteItem]
    /// The archived count value.
    public let archivedCount: Int?
    /// The archived last updated value.
    public let archivedLastUpdated: String?

    public init(items: [WebsiteItem], archivedCount: Int? = nil, archivedLastUpdated: String? = nil) {
        self.items = items
        self.archivedCount = archivedCount
        self.archivedLastUpdated = archivedLastUpdated
    }

    enum CodingKeys: String, CodingKey {
        case items
        case archivedCount = "archived_count"
        case archivedLastUpdated = "archived_last_updated"
    }
}

/// Represents a website detail struct.
public struct WebsiteDetail: Codable, Identifiable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The url value.
    public let url: String
    /// The url full value.
    public let urlFull: String?
    /// The domain value.
    public let domain: String
    /// The content value.
    public let content: String
    /// The source value.
    public let source: String?
    /// The saved at value.
    public let savedAt: String?
    /// The published at value.
    public let publishedAt: String?
    /// The pinned value.
    public let pinned: Bool
    /// The pinned order value.
    public let pinnedOrder: Int?
    /// The archived value.
    public let archived: Bool
    /// The favicon url value.
    public let faviconUrl: String?
    /// The favicon r2 key value.
    public let faviconR2Key: String?
    /// The youtube transcripts value.
    public let youtubeTranscripts: [String: WebsiteTranscriptEntry]?
    /// The reading time value.
    public var readingTime: String?
    /// The updated at value.
    public let updatedAt: String?
    /// The last opened at value.
    public let lastOpenedAt: String?
}

/// Represents a website transcript response struct.
public struct WebsiteTranscriptResponse: Decodable {
    /// The ready website value.
    public let readyWebsite: WebsiteDetail?
    /// The queued status value.
    public let queuedStatus: String?
    /// The queued file id value.
    public let queuedFileId: String?

    public init(
        readyWebsite: WebsiteDetail? = nil,
        queuedStatus: String? = nil,
        queuedFileId: String? = nil
    ) {
        self.readyWebsite = readyWebsite
        self.queuedStatus = queuedStatus
        self.queuedFileId = queuedFileId
    }

    public init(from decoder: Decoder) throws {
        if let detail = try? WebsiteDetail(from: decoder) {
            readyWebsite = detail
            queuedStatus = nil
            queuedFileId = nil
            return
        }
        let envelope = try TranscriptQueueEnvelope(from: decoder)
        readyWebsite = nil
        queuedStatus = envelope.data?.status
        queuedFileId = envelope.data?.fileId
    }
}

private struct TranscriptQueueEnvelope: Decodable {
    let success: Bool
    let data: TranscriptQueueData?
}

private struct TranscriptQueueData: Decodable {
    let status: String?
    let fileId: String?
}

/// Represents a website save response struct.
public struct WebsiteSaveResponse: Codable {
    /// The success value.
    public let success: Bool
    /// The canonical saved website payload.
    public let website: WebsiteDetail?
}

/// Represents a website sync response struct.
public struct WebsiteSyncResponse: Codable {
    /// The applied value.
    public let applied: [String]
    /// The websites value.
    public let websites: [WebsiteItem]
    /// The conflicts value.
    public let conflicts: [WebsiteSyncConflict]
    /// The updates value.
    public let updates: WebsiteSyncUpdates?
    /// The server updated since value.
    public let serverUpdatedSince: String?
}

/// Represents a website sync updates struct.
public struct WebsiteSyncUpdates: Codable {
    /// The items value.
    public let items: [WebsiteItem]
}

/// Represents a website sync conflict struct.
public struct WebsiteSyncConflict: Codable {
    /// The operation id value.
    public let operationId: String
    /// The op value.
    public let op: String?
    /// The id value.
    public let id: String?
    /// The client updated at value.
    public let clientUpdatedAt: String?
    /// The server updated at value.
    public let serverUpdatedAt: String?
    /// The server website value.
    public let serverWebsite: WebsiteItem?
    /// The reason value.
    public let reason: String?
}
