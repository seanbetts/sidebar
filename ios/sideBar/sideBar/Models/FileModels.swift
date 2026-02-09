import Foundation
import sideBarShared

/// Represents a file node type enum.
public enum FileNodeType: String, Codable {
    case file
    case directory
}

/// Represents a file node struct.
public struct FileNode: Codable {
    /// The name value.
    public let name: String
    /// The path value.
    public let path: String
    /// The type value.
    public let type: FileNodeType
    /// The size value.
    public let size: Int?
    /// The modified value.
    public let modified: Double?
    /// The created value.
    public let created: Double?
    /// The children value.
    public let children: [FileNode]?
    /// The expanded value.
    public let expanded: Bool?
    /// The pinned value.
    public let pinned: Bool?
    /// The pinned order value.
    public let pinnedOrder: Int?
    /// The archived value.
    public let archived: Bool?
    /// The folder marker value.
    public let folderMarker: Bool?
}

/// Represents a file tree struct.
public struct FileTree: Codable {
    /// The children value.
    public let children: [FileNode]
    /// The archived count value.
    public let archivedCount: Int?
    /// The archived last updated value.
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

/// Represents an archived summary struct.
public struct ArchivedSummary: Codable, Equatable {
    /// The count value.
    public let count: Int?
    /// The last updated value.
    public let lastUpdated: String?

    public init(count: Int? = nil, lastUpdated: String? = nil) {
        self.count = count
        self.lastUpdated = lastUpdated
    }

    /// Indicates whether empty.
    public var isEmpty: Bool {
        count == nil && lastUpdated == nil
    }
}

/// Represents a file content struct.
public struct FileContent: Codable {
    /// The content value.
    public let content: String
    /// The name value.
    public let name: String
    /// The path value.
    public let path: String
    /// The modified value.
    public let modified: Double?
}

/// Represents an ingested file meta struct.
public struct IngestedFileMeta: Codable {
    /// The id value.
    public let id: String
    /// The filename original value.
    public let filenameOriginal: String
    /// The path value.
    public let path: String?
    /// The mime original value.
    public let mimeOriginal: String
    /// The size bytes value.
    public let sizeBytes: Int
    /// The sha256 value.
    public let sha256: String?
    /// The pinned value.
    public let pinned: Bool?
    /// The pinned order value.
    public let pinnedOrder: Int?
    /// The category value.
    public let category: String?
    /// The source url value.
    public let sourceUrl: String?
    /// The source metadata value.
    public let sourceMetadata: [String: AnyCodable]?
    /// The created at value.
    public let createdAt: String
    /// The updated at value.
    public let updatedAt: String?
    /// The deleted at value.
    public let deletedAt: String?
}

/// Represents an ingestion job struct.
public struct IngestionJob: Codable {
    /// The status value.
    public let status: String?
    /// The stage value.
    public let stage: String?
    /// The error code value.
    public let errorCode: String?
    /// The error message value.
    public let errorMessage: String?
    /// The user message value.
    public let userMessage: String?
    /// The progress value.
    public let progress: Double?
    /// The attempts value.
    public let attempts: Int
    /// The updated at value.
    public let updatedAt: String?
}

/// Represents an ingestion list item struct.
public struct IngestionListItem: Codable {
    /// The file value.
    public let file: IngestedFileMeta
    /// The job value.
    public let job: IngestionJob
    /// The recommended viewer value.
    public let recommendedViewer: String?
}

extension IngestionListItem: StatusFilterable {
    /// The status value value.
    public var statusValue: String {
        job.status ?? ""
    }
}

/// Represents an ingestion list response struct.
public struct IngestionListResponse: Codable {
    /// The items value.
    public let items: [IngestionListItem]
}

/// Represents an ingestion sync response struct.
public struct IngestionSyncResponse: Codable {
    /// The applied value.
    public let applied: [String]
    /// The files value.
    public let files: [IngestedFileMeta]
    /// The conflicts value.
    public let conflicts: [IngestionSyncConflict]
    /// The updates value.
    public let updates: IngestionSyncUpdates?
    /// The server updated since value.
    public let serverUpdatedSince: String?
}

/// Represents an ingestion sync updates struct.
public struct IngestionSyncUpdates: Codable {
    /// The items value.
    public let items: [IngestedFileMeta]
}

/// Represents an ingestion sync conflict struct.
public struct IngestionSyncConflict: Codable {
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
    /// The server file value.
    public let serverFile: IngestedFileMeta?
    /// The reason value.
    public let reason: String?
}

/// Represents an ingestion meta response struct.
public struct IngestionMetaResponse: Codable {
    /// The file value.
    public let file: IngestedFileMeta
    /// The job value.
    public let job: IngestionJob
    /// The derivatives value.
    public let derivatives: [IngestionDerivative]
    /// The recommended viewer value.
    public let recommendedViewer: String?
}

/// Represents an ingestion derivative struct.
public struct IngestionDerivative: Codable {
    /// The id value.
    public let id: String
    /// The kind value.
    public let kind: String
    /// The storage key value.
    public let storageKey: String
    /// The mime value.
    public let mime: String
    /// The size bytes value.
    public let sizeBytes: Int
}

/// Represents a spreadsheet payload struct.
public struct SpreadsheetPayload: Codable {
    /// The sheets value.
    public let sheets: [SpreadsheetSheet]
}

/// Represents a spreadsheet sheet struct.
public struct SpreadsheetSheet: Codable {
    /// The name value.
    public let name: String
    /// The rows value.
    public let rows: [[String]]
    /// The header row value.
    public let headerRow: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case rows
        case headerRow = "header_row"
    }
}
