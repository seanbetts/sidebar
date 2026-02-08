import Foundation
import Combine

public struct WebsiteItem: Codable, Identifiable {
    public let id: String
    public let title: String
    public let url: String
    public let domain: String
    public let savedAt: String?
    public let publishedAt: String?
    public let pinned: Bool
    public let pinnedOrder: Int?
    public let archived: Bool
    public let faviconUrl: String?
    public let faviconR2Key: String?
    public let youtubeTranscripts: [String: WebsiteTranscriptEntry]?
    public let readingTime: String?
    public let updatedAt: String?
    public let lastOpenedAt: String?
    public let deletedAt: String?
}

public struct WebsitesResponse: Codable {
    public let items: [WebsiteItem]
    public let archivedCount: Int?
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

public struct WebsiteDetail: Codable, Identifiable {
    public let id: String
    public let title: String
    public let url: String
    public let urlFull: String?
    public let domain: String
    public let content: String
    public let source: String?
    public let savedAt: String?
    public let publishedAt: String?
    public let pinned: Bool
    public let pinnedOrder: Int?
    public let archived: Bool
    public let faviconUrl: String?
    public let faviconR2Key: String?
    public let youtubeTranscripts: [String: WebsiteTranscriptEntry]?
    public var readingTime: String?
    public let updatedAt: String?
    public let lastOpenedAt: String?
}

public struct WebsiteTranscriptEntry: Codable, Equatable {
    public let status: String?
    public let fileId: String?
    public let updatedAt: String?
    public let error: String?
}

public struct WebsiteTranscriptResponse: Decodable {
    public let readyWebsite: WebsiteDetail?
    public let queuedStatus: String?
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

public struct WebsiteQuickSaveResponse: Codable {
    public let success: Bool
    public let data: WebsiteQuickSaveData?
}

public struct WebsiteQuickSaveData: Codable {
    public let jobId: String
}

public struct WebsiteQuickSaveJob: Codable {
    public let id: String
    public let status: String
    public let errorMessage: String?
    public let websiteId: String?
    public let createdAt: String?
    public let updatedAt: String?
}

public struct WebsiteSaveResponse: Codable {
    public let success: Bool
    public let data: WebsiteSaveData?
}

public struct WebsiteSaveData: Codable {
    public let id: String
    public let title: String
    public let url: String
    public let domain: String
}

public struct WebsiteSyncResponse: Codable {
    public let applied: [String]
    public let websites: [WebsiteItem]
    public let conflicts: [WebsiteSyncConflict]
    public let updates: WebsiteSyncUpdates?
    public let serverUpdatedSince: String?
}

public struct WebsiteSyncUpdates: Codable {
    public let items: [WebsiteItem]
}

public struct WebsiteSyncConflict: Codable {
    public let operationId: String
    public let op: String?
    public let id: String?
    public let clientUpdatedAt: String?
    public let serverUpdatedAt: String?
    public let serverWebsite: WebsiteItem?
    public let reason: String?
}
