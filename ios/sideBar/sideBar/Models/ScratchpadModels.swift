import Foundation
import Combine

/// Represents a scratchpad response struct.
public struct ScratchpadResponse: Codable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The content value.
    public let content: String
    /// The updated at value.
    public let updatedAt: String?
}

/// Represents a scratchpad mode enum.
public enum ScratchpadMode: String, Codable {
    case append
    case prepend
    case replace
}

/// Represents a scratchpad update request struct.
public struct ScratchpadUpdateRequest: Codable {
    /// The content value.
    public let content: String
    /// The mode value.
    public let mode: ScratchpadMode?
}
