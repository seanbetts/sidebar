import Foundation

public protocol RealtimeEventHandler: AnyObject {
    func handleNoteEvent(_ payload: RealtimePayload<NoteRealtimeRecord>)
    func handleWebsiteEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>)
    func handleIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>)
    func handleFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>)
}

public final class SupabaseRealtimeAdapter: RealtimeClient {
    public weak var handler: RealtimeEventHandler?

    public init(handler: RealtimeEventHandler? = nil) {
        self.handler = handler
    }

    public func start(userId: String, accessToken: String?) async {
        _ = userId
        _ = accessToken
    }

    public func stop() {
    }
}

public struct NoteRealtimeRecord: Codable {
    public let id: String
    public let title: String?
    public let content: String?
    public let metadata: [String: AnyCodable]?
    public let updatedAt: String?
    public let deletedAt: String?
}

public struct WebsiteRealtimeRecord: Codable {
    public let id: String
    public let title: String?
    public let url: String?
    public let domain: String?
    public let metadata: [String: AnyCodable]?
    public let savedAt: String?
    public let publishedAt: String?
    public let updatedAt: String?
    public let lastOpenedAt: String?
    public let deletedAt: String?
}

public struct IngestedFileRealtimeRecord: Codable {
    public let id: String
    public let filenameOriginal: String?
    public let path: String?
    public let mimeOriginal: String?
    public let sizeBytes: Int?
    public let sha256: String?
    public let sourceUrl: String?
    public let sourceMetadata: [String: AnyCodable]?
    public let pinned: Bool?
    public let pinnedOrder: Int?
    public let createdAt: String?
    public let updatedAt: String?
    public let deletedAt: String?
}

public struct FileJobRealtimeRecord: Codable {
    public let fileId: String
    public let status: String?
    public let stage: String?
    public let errorCode: String?
    public let errorMessage: String?
    public let attempts: Int?
    public let updatedAt: String?
}
