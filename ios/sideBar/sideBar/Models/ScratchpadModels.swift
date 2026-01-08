import Foundation

public struct ScratchpadResponse: Codable {
    public let id: String
    public let title: String
    public let content: String
    public let updatedAt: String?
}

public enum ScratchpadMode: String, Codable {
    case append
    case prepend
    case replace
}

public struct ScratchpadUpdateRequest: Codable {
    public let content: String
    public let mode: ScratchpadMode?
}
