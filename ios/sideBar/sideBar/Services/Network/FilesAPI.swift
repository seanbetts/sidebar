import Foundation

/// Defines the requirements for FilesProviding.
public protocol FilesProviding {
    func listTree(basePath: String) async throws -> FileTree
    func getContent(basePath: String, path: String) async throws -> FileContent
    func download(basePath: String, path: String) async throws -> Data
}

/// API client for file tree and content endpoints.
public struct FilesAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func listTree(basePath: String = "documents") async throws -> FileTree {
        let encoded = basePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? basePath
        let path = "files/tree?basePath=\(encoded)"
        return try await client.request(path)
    }

    public func search(query: String, basePath: String = "documents", limit: Int = 50) async throws -> [FileNode] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let baseEncoded = basePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? basePath
        let path = "files/search?query=\(encoded)&basePath=\(baseEncoded)&limit=\(limit)"
        struct SearchResponse: Codable { let items: [FileNode] }
        let response: SearchResponse = try await client.request(path, method: "POST")
        return response.items
    }

    public func createFolder(basePath: String = "documents", path: String) async throws {
        struct FolderRequest: Codable { let basePath: String; let path: String }
        try await client.requestVoid("files/folder", method: "POST", body: FolderRequest(basePath: basePath, path: path))
    }

    public func rename(basePath: String = "documents", oldPath: String, newName: String) async throws {
        struct RenameRequest: Codable { let basePath: String; let oldPath: String; let newName: String }
        try await client.requestVoid("files/rename", method: "POST", body: RenameRequest(basePath: basePath, oldPath: oldPath, newName: newName))
    }

    public func move(basePath: String = "documents", path: String, destination: String) async throws {
        struct MoveRequest: Codable { let basePath: String; let path: String; let destination: String }
        try await client.requestVoid("files/move", method: "POST", body: MoveRequest(basePath: basePath, path: path, destination: destination))
    }

    public func delete(basePath: String = "documents", path: String) async throws {
        struct DeleteRequest: Codable { let basePath: String; let path: String }
        try await client.requestVoid("files/delete", method: "POST", body: DeleteRequest(basePath: basePath, path: path))
    }

    public func getContent(basePath: String = "documents", path: String) async throws -> FileContent {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let requestPath = "files/content?basePath=\(basePath)&path=\(encoded)"
        return try await client.request(requestPath)
    }

    public func updateContent(basePath: String = "documents", path: String, content: String) async throws {
        struct UpdateRequest: Codable { let basePath: String; let path: String; let content: String }
        try await client.requestVoid("files/content", method: "POST", body: UpdateRequest(basePath: basePath, path: path, content: content))
    }

    public func download(basePath: String = "documents", path: String) async throws -> Data {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let baseEncoded = basePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? basePath
        let requestPath = "files/download?basePath=\(baseEncoded)&path=\(encoded)"
        return try await client.requestData(requestPath)
    }
}

extension FilesAPI: FilesProviding {}
