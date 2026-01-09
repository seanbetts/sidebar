import Foundation

public protocol NotesProviding {
    func listTree() async throws -> FileTree
    func getNote(id: String) async throws -> NotePayload
}

public struct NotesAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func listTree() async throws -> FileTree {
        try await client.request("notes/tree")
    }

    public func search(query: String, limit: Int = 50) async throws -> [FileNode] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let path = "notes/search?query=\(encoded)&limit=\(limit)"
        struct NotesSearchResponse: Codable {
            let items: [FileNode]
        }
        let response: NotesSearchResponse = try await client.request(path, method: "POST")
        return response.items
    }

    public func getNote(id: String) async throws -> NotePayload {
        try await client.request("notes/\(id)")
    }

    public func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        try await client.request("notes", method: "POST", body: request)
    }

    public func updateNote(id: String, content: String) async throws -> NotePayload {
        try await client.request("notes/\(id)", method: "PATCH", body: NoteUpdateRequest(content: content))
    }

    public func renameNote(id: String, newName: String) async throws -> NotePayload {
        try await client.request("notes/\(id)/rename", method: "PATCH", body: RenameRequest(newName: newName))
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
        struct FolderRequest: Codable { let oldPath: String; let newName: String }
        try await client.requestVoid("notes/folders/rename", method: "PATCH", body: FolderRequest(oldPath: oldPath, newName: newName))
    }

    public func moveFolder(oldPath: String, newParent: String) async throws {
        struct FolderRequest: Codable { let oldPath: String; let newParent: String }
        try await client.requestVoid("notes/folders/move", method: "PATCH", body: FolderRequest(oldPath: oldPath, newParent: newParent))
    }

    public func deleteFolder(path: String) async throws {
        struct FolderRequest: Codable { let path: String }
        try await client.requestVoid("notes/folders", method: "DELETE", body: FolderRequest(path: path))
    }
}

extension NotesAPI: NotesProviding {}

public struct NotePayload: Codable {
    public let id: String
    public let name: String
    public let content: String
    public let path: String
    public let modified: Double?
}

public struct NoteCreateRequest: Codable {
    public let content: String
    public let title: String?
    public let path: String?
    public let folder: String?
}

public struct NoteUpdateRequest: Codable {
    public let content: String
}

public struct RenameRequest: Codable {
    public let newName: String
}

public struct MoveRequest: Codable {
    public let folder: String
}

public struct ArchiveRequest: Codable {
    public let archived: Bool
}

public struct PinRequest: Codable {
    public let pinned: Bool
}
