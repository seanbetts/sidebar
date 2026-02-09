import Foundation
import Combine

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

/// Represents a website transcript entry struct.
public struct WebsiteTranscriptEntry: Codable, Equatable {
    /// The status value.
    public let status: String?
    /// The file id value.
    public let fileId: String?
    /// The updated at value.
    public let updatedAt: String?
    /// The error value.
    public let error: String?
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

/// Represents a website quick save response struct.
public struct WebsiteQuickSaveResponse: Codable {
    /// The success value.
    public let success: Bool
    /// The data value.
    public let data: WebsiteQuickSaveData?
}

/// Represents a website quick save data struct.
public struct WebsiteQuickSaveData: Codable {
    /// The job id value.
    public let jobId: String
}

/// Represents a website quick save job struct.
public struct WebsiteQuickSaveJob: Codable {
    /// The id value.
    public let id: String
    /// The status value.
    public let status: String
    /// The error message value.
    public let errorMessage: String?
    /// The website id value.
    public let websiteId: String?
    /// The created at value.
    public let createdAt: String?
    /// The updated at value.
    public let updatedAt: String?
}

/// Represents a website save response struct.
public struct WebsiteSaveResponse: Codable {
    /// The success value.
    public let success: Bool
    /// The data value.
    public let data: WebsiteSaveData?
}

/// Represents a website save data struct.
public struct WebsiteSaveData: Codable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The url value.
    public let url: String
    /// The domain value.
    public let domain: String
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
