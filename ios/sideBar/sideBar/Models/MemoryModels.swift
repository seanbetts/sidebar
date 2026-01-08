import Foundation

public struct MemoryItem: Codable, Identifiable {
    public let id: String
    public let path: String
    public let content: String
    public let createdAt: String
    public let updatedAt: String
}

public struct MemoryCreate: Codable {
    public let path: String
    public let content: String
}

public struct MemoryUpdate: Codable {
    public let path: String?
    public let content: String?
}
