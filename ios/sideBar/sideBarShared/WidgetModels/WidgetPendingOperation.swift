import Foundation

/// Generic pending operation from widget to main app.
public struct WidgetPendingOperation<ActionType: Codable & Equatable>: Codable, Equatable {
    /// Unique ID for this operation, used for deduplication.
    public let id: String

    /// ID of the item being operated on, empty for global actions like add-new.
    public let itemId: String

    /// The type-specific action to perform.
    public let action: ActionType

    /// When this operation was recorded.
    public let timestamp: Date

    public init(itemId: String, action: ActionType) {
        self.id = UUID().uuidString
        self.itemId = itemId
        self.action = action
        self.timestamp = Date()
    }
}

/// Actions that can be performed on tasks from widgets.
public enum TaskWidgetAction: String, Codable, Equatable {
    case complete
    case snooze
    case addNew
}

/// Actions that can be performed on notes from widgets.
public enum NoteWidgetAction: String, Codable, Equatable {
    case archive
    case pin
    case addNew
}

/// Actions that can be performed on websites from widgets.
public enum WebsiteWidgetAction: String, Codable, Equatable {
    case archive
    case pin
    case open
}

/// Actions that can be performed on files from widgets.
public enum FileWidgetAction: String, Codable, Equatable {
    case pin
    case open
}
