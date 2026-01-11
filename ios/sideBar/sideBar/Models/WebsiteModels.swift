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
    public let youtubeTranscripts: [String: WebsiteTranscriptEntry]?
    public let updatedAt: String?
    public let lastOpenedAt: String?
}

public struct WebsitesResponse: Codable {
    public let items: [WebsiteItem]
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
    public let youtubeTranscripts: [String: WebsiteTranscriptEntry]?
    public let updatedAt: String?
    public let lastOpenedAt: String?
}

public struct WebsiteTranscriptEntry: Codable {
    public let status: String?
    public let fileId: String?
    public let updatedAt: String?
    public let error: String?
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
