import Foundation

public enum FileNodeType: String, Codable {
    case file
    case directory
}

public struct FileNode: Codable {
    public let name: String
    public let path: String
    public let type: FileNodeType
    public let size: Int?
    public let modified: String?
    public let children: [FileNode]?
    public let expanded: Bool?
    public let pinned: Bool?
    public let pinnedOrder: Int?
    public let archived: Bool?
    public let folderMarker: Bool?
}

public struct FileTree: Codable {
    public let children: [FileNode]
}

public struct IngestedFileMeta: Codable {
    public let id: String
    public let filenameOriginal: String
    public let path: String?
    public let mimeOriginal: String
    public let sizeBytes: Int
    public let sha256: String?
    public let pinned: Bool?
    public let pinnedOrder: Int?
    public let category: String?
    public let sourceUrl: String?
    public let sourceMetadata: [String: AnyCodable]?
    public let createdAt: String
}

public struct IngestionJob: Codable {
    public let status: String?
    public let stage: String?
    public let errorCode: String?
    public let errorMessage: String?
    public let userMessage: String?
    public let progress: Double?
    public let attempts: Int
    public let updatedAt: String?
}

public struct IngestionListItem: Codable {
    public let file: IngestedFileMeta
    public let job: IngestionJob
    public let recommendedViewer: String?
}

public struct IngestionListResponse: Codable {
    public let items: [IngestionListItem]
}

public struct IngestionMetaResponse: Codable {
    public let file: IngestedFileMeta
    public let job: IngestionJob
    public let derivatives: [IngestionDerivative]
    public let recommendedViewer: String?
}

public struct IngestionDerivative: Codable {
    public let id: String
    public let kind: String
    public let storageKey: String
    public let mime: String
    public let sizeBytes: Int
}
