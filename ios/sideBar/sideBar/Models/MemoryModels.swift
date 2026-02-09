import Foundation

/// Represents a memory item struct.
public struct MemoryItem: Codable, Identifiable {
    /// The id value.
    public let id: String
    /// The path value.
    public let path: String
    /// The content value.
    public let content: String
    /// The created at value.
    public let createdAt: String
    /// The updated at value.
    public let updatedAt: String
}

/// Represents a memory create struct.
public struct MemoryCreate: Codable {
    /// The path value.
    public let path: String
    /// The content value.
    public let content: String
}

/// Represents a memory update struct.
public struct MemoryUpdate: Codable {
    /// The path value.
    public let path: String?
    /// The content value.
    public let content: String?
}
