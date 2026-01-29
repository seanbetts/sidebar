import Foundation
import sideBarShared

/// Defines ChatStreamEventType.
public enum ChatStreamEventType: String {
    case token
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case complete
    case error
    case noteCreated = "note_created"
    case noteUpdated = "note_updated"
    case notePinned = "note_pinned"
    case noteMoved = "note_moved"
    case noteDeleted = "note_deleted"
    case websiteSaved = "website_saved"
    case websitePinned = "website_pinned"
    case websiteArchived = "website_archived"
    case websiteDeleted = "website_deleted"
    case ingestionUpdated = "ingestion_updated"
    case themeSet = "ui_theme_set"
    case scratchpadUpdated = "scratchpad_updated"
    case scratchpadCleared = "scratchpad_cleared"
    case promptPreview = "prompt_preview"
    case toolStart = "tool_start"
    case toolEnd = "tool_end"
    case memoryCreated = "memory_created"
    case memoryUpdated = "memory_updated"
    case memoryDeleted = "memory_deleted"
}

/// Represents ChatStreamEvent.
public struct ChatStreamEvent {
    public let type: ChatStreamEventType
    public let data: AnyCodable?

    public init(type: ChatStreamEventType, data: AnyCodable?) {
        self.type = type
        self.data = data
    }
}
