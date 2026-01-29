import Foundation
import sideBarShared

/// Defines the requirements for NotesProviding.
public protocol NotesProviding {
    func listTree() async throws -> FileTree
    func getNote(id: String) async throws -> NotePayload
    func search(query: String, limit: Int) async throws -> [FileNode]
    func updateNote(id: String, content: String) async throws -> NotePayload
    func createNote(request: NoteCreateRequest) async throws -> NotePayload
    func renameNote(id: String, newName: String) async throws -> NotePayload
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
        try await client.request("notes", method: "POST", body: request)
    }

    public func updateNote(id: String, content: String) async throws -> NotePayload {
        try await client.request("notes/\(id)", method: "PATCH", body: NoteUpdateRequest(content: content))
    }

    public func renameNote(id: String, newName: String) async throws -> NotePayload {
        struct RenamePayload: Encodable { let newName: String }
        return try await client.request("notes/\(id)/rename", method: "PATCH", body: RenamePayload(newName: newName))
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
public struct NotePayload: Codable {
    public let id: String
    public let name: String
    public let content: String
    public let path: String
    public let modified: Double?
}

/// Request body for creating a note.
public struct NoteCreateRequest: Codable {
    public let content: String
    public let title: String?
    public let path: String?
    public let folder: String?
}

/// Request body for updating note content.
public struct NoteUpdateRequest: Codable {
    public let content: String
}

/// Request body for renaming a note.
public struct RenameRequest: Codable {
    public let newName: String
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
