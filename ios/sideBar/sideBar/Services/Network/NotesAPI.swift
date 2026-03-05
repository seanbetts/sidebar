import Foundation
import sideBarShared

/// Defines the requirements for NotesProviding.
public protocol NotesProviding {
    func listTree() async throws -> FileTree
    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree
    func getNote(id: String) async throws -> NotePayload
    func search(query: String, limit: Int) async throws -> [FileNode]
    func updateNote(id: String, content: String) async throws -> NotePayload
    func createNote(request: NoteCreateRequest) async throws -> NotePayload
    func moveNote(id: String, folder: String) async throws -> NotePayload
    func archiveNote(id: String, archived: Bool) async throws -> NotePayload
    func pinNote(id: String, pinned: Bool) async throws -> NotePayload
    func updatePinnedOrder(ids: [String]) async throws
    func deleteNote(id: String) async throws -> NotePayload
    func createFolder(path: String) async throws
    func renameFolder(oldPath: String, newName: String) async throws
    func moveFolder(oldPath: String, newParent: String) async throws
    func deleteFolder(path: String) async throws
}

/// API client for note endpoints.
public struct NotesAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func listTree() async throws -> FileTree {
        try await client.request("notes/tree")
    }

    public func listArchivedTree(limit: Int = 200, offset: Int = 0) async throws -> FileTree {
        var queryItems: [URLQueryItem] = []
        if limit > 0 {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if offset > 0 {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        let path = APIClient.path("notes/archived", queryItems: queryItems)
        return try await client.request(path)
    }

    public func search(query: String, limit: Int = 50) async throws -> [FileNode] {
        struct NotesSearchRequest: Encodable {
            let query: String
            let limit: Int
        }
        struct NotesSearchResponse: Codable {
            let items: [FileNode]
        }
        let response: NotesSearchResponse = try await client.request(
            "notes/search",
            method: "POST",
            body: NotesSearchRequest(query: query, limit: limit)
        )
        return response.items
    }

    public func getNote(id: String) async throws -> NotePayload {
        try await client.request("notes/\(id)")
    }

    public func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        try await client.request(
            "notes",
            method: "POST",
            body: request.canonicalized()
        )
    }

    public func updateNote(id: String, content: String) async throws -> NotePayload {
        let normalized = NotesRichTextCodec.normalizeWriteInput(content: content)
        return try await client.request(
            "notes/\(id)",
            method: "PATCH",
            body: NoteUpdateRequest(
                content: normalized.content,
                plainText: normalized.plainText
            )
        )
    }

    public func moveNote(id: String, folder: String) async throws -> NotePayload {
        try await client.request("notes/\(id)/move", method: "PATCH", body: MoveRequest(folder: folder))
    }

    public func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        try await client.request("notes/\(id)/archive", method: "PATCH", body: ArchiveRequest(archived: archived))
    }

    public func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        try await client.request("notes/\(id)/pin", method: "PATCH", body: PinRequest(pinned: pinned))
    }

    public func updatePinnedOrder(ids: [String]) async throws {
        struct PinnedOrderRequest: Codable { let order: [String] }
        try await client.requestVoid("notes/pinned-order", method: "PATCH", body: PinnedOrderRequest(order: ids))
    }

    public func deleteNote(id: String) async throws -> NotePayload {
        try await client.request("notes/\(id)", method: "DELETE")
    }

    public func createFolder(path: String) async throws {
        struct FolderRequest: Codable { let path: String }
        try await client.requestVoid("notes/folders", method: "POST", body: FolderRequest(path: path))
    }

    public func renameFolder(oldPath: String, newName: String) async throws {
        let payload = ["oldPath": oldPath, "newName": newName]
        try await client.requestVoid("notes/folders/rename", method: "PATCH", body: payload)
    }

    public func moveFolder(oldPath: String, newParent: String) async throws {
        let payload = ["oldPath": oldPath, "newParent": newParent]
        try await client.requestVoid("notes/folders/move", method: "PATCH", body: payload)
    }

    public func deleteFolder(path: String) async throws {
        struct FolderRequest: Codable { let path: String }
        try await client.requestVoid("notes/folders", method: "DELETE", body: FolderRequest(path: path))
    }
}

extension NotesAPI: NotesProviding {}

/// Response payload for note data.
public struct NotePayload: Codable, Equatable {
    public let id: String
    public let name: String
    /// Canonical Base64 RTF payload from backend contract.
    public let content: String
    /// Explicit plain-text cache for list/search/prompt/export paths.
    public let plainText: String
    public let path: String
    public let modified: Double?
    public let created: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case content
        case path
        case modified
        case created
        case plainText = "plain_text"
        case plainTextCamel = "plainText"
    }

    public init(
        id: String,
        name: String,
        content: String,
        plainText: String? = nil,
        path: String,
        modified: Double?,
        created: Double?
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.plainText = plainText ?? content
        self.path = path
        self.modified = modified
        self.created = created
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        modified = try container.decodeIfPresent(Double.self, forKey: .modified)
        created = try container.decodeIfPresent(Double.self, forKey: .created)
        let rawContent = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        let decodedPlainText = try container.decodeIfPresent(String.self, forKey: .plainText)
            ?? container.decodeIfPresent(String.self, forKey: .plainTextCamel)
        content = rawContent
        plainText = decodedPlainText ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(content, forKey: .content)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(modified, forKey: .modified)
        try container.encodeIfPresent(created, forKey: .created)
        try container.encode(plainText, forKey: .plainText)
    }
}

/// Request body for creating a note.
public struct NoteCreateRequest: Codable {
    public let content: String
    public let title: String?
    public let path: String?
    public let folder: String?
    public let plainText: String?

    enum CodingKeys: String, CodingKey {
        case content
        case title
        case path
        case folder
        case plainText = "plain_text"
    }

    public init(
        content: String,
        title: String? = nil,
        path: String? = nil,
        folder: String? = nil,
        plainText: String? = nil
    ) {
        self.content = content
        self.title = title
        self.path = path
        self.folder = folder
        self.plainText = plainText
    }

    func canonicalized() -> NoteCreateRequest {
        let normalized = NotesRichTextCodec.normalizeWriteInput(
            content: content,
            plainText: plainText
        )
        return NoteCreateRequest(
            content: normalized.content,
            title: title,
            path: path,
            folder: folder,
            plainText: normalized.plainText
        )
    }
}

/// Request body for updating note content.
public struct NoteUpdateRequest: Codable {
    public let content: String
    public let plainText: String?

    enum CodingKeys: String, CodingKey {
        case content
        case plainText = "plain_text"
    }

    public init(content: String, plainText: String? = nil) {
        self.content = content
        self.plainText = plainText
    }
}

/// Request body for moving a note to a folder.
public struct MoveRequest: Codable {
    public let folder: String
}

/// Request body for archiving or unarchiving a note.
public struct ArchiveRequest: Codable {
    public let archived: Bool
}

/// Request body for pinning or unpinning a note.
public struct PinRequest: Codable {
    public let pinned: Bool
}
