import Foundation
import sideBarShared

public enum FileNodeType: String, Codable {
    case file
    case directory
}

public struct FileNode: Codable {
    public let name: String
    public let path: String
    public let type: FileNodeType
    public let size: Int?
    public let modified: Double?
    public let children: [FileNode]?
    public let expanded: Bool?
    public let pinned: Bool?
    public let pinnedOrder: Int?
    public let archived: Bool?
    public let folderMarker: Bool?
}

public struct FileTree: Codable {
    public let children: [FileNode]
    public let archivedCount: Int?
    public let archivedLastUpdated: String?

    public init(children: [FileNode], archivedCount: Int? = nil, archivedLastUpdated: String? = nil) {
        self.children = children
        self.archivedCount = archivedCount
        self.archivedLastUpdated = archivedLastUpdated
    }

    enum CodingKeys: String, CodingKey {
        case children
        case archivedCount = "archived_count"
        case archivedLastUpdated = "archived_last_updated"
    }
}

public struct ArchivedSummary: Codable, Equatable {
    public let count: Int?
    public let lastUpdated: String?

    public init(count: Int? = nil, lastUpdated: String? = nil) {
        self.count = count
        self.lastUpdated = lastUpdated
    }

    public var isEmpty: Bool {
        count == nil && lastUpdated == nil
    }
}

public struct FileContent: Codable {
    public let content: String
    public let name: String
    public let path: String
    public let modified: Double?
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
    public let updatedAt: String?
    public let deletedAt: String?
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

extension IngestionListItem: StatusFilterable {
    public var statusValue: String {
        job.status ?? ""
    }
}

public struct IngestionListResponse: Codable {
    public let items: [IngestionListItem]
}

public struct IngestionSyncResponse: Codable {
    public let applied: [String]
    public let files: [IngestedFileMeta]
    public let conflicts: [IngestionSyncConflict]
    public let updates: IngestionSyncUpdates?
    public let serverUpdatedSince: String?
}

public struct IngestionSyncUpdates: Codable {
    public let items: [IngestedFileMeta]
}

public struct IngestionSyncConflict: Codable {
    public let operationId: String
    public let op: String?
    public let id: String?
    public let clientUpdatedAt: String?
    public let serverUpdatedAt: String?
    public let serverFile: IngestedFileMeta?
    public let reason: String?
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

public struct SpreadsheetPayload: Codable {
    public let sheets: [SpreadsheetSheet]
}

public struct SpreadsheetSheet: Codable {
    public let name: String
    public let rows: [[String]]
    public let headerRow: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case rows
        case headerRow = "header_row"
    }
}
