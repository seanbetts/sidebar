import Foundation

enum ServerSnapshotPayload: Codable, Equatable {
    case note(NoteSnapshot)
    case website(WebsiteSnapshot)
    case file(FileSnapshot)
}

struct ServerSnapshot: Codable, Equatable {
    let entityType: WriteEntityType
    let entityId: String
    let capturedAt: Date
    let payload: ServerSnapshotPayload
}

struct NoteSnapshot: Codable, Equatable {
    let modified: Double?
    let name: String?
    let path: String?
    let pinned: Bool?
    let pinnedOrder: Int?
    let archived: Bool?
}

struct WebsiteSnapshot: Codable, Equatable {
    let updatedAt: String?
    let title: String?
    let pinned: Bool?
    let pinnedOrder: Int?
    let archived: Bool?
}

struct FileSnapshot: Codable, Equatable {
    let filenameOriginal: String?
    let pinned: Bool?
    let pinnedOrder: Int?
    let path: String?
}
