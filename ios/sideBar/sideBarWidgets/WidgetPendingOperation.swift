import Foundation

// MARK: - Widget Pending Operation

/// Generic pending operation from widget to main app
public struct WidgetPendingOperation<ActionType: Codable & Equatable>: Codable, Equatable {
  /// Unique ID for this operation (for deduplication)
  public let id: String

  /// ID of the item being operated on (empty for global actions like "add new")
  public let itemId: String

  /// The type-specific action to perform
  public let action: ActionType

  /// When this operation was recorded
  public let timestamp: Date

  public init(itemId: String, action: ActionType) {
    self.id = UUID().uuidString
    self.itemId = itemId
    self.action = action
    self.timestamp = Date()
  }
}

// MARK: - Task Actions

/// Actions that can be performed on tasks from widgets
public enum TaskWidgetAction: String, Codable, Equatable {
  /// Mark task as complete
  case complete
  /// Snooze task to later
  case snooze
  /// Intent to add a new task (itemId will be empty)
  case addNew
}

// MARK: - Note Actions

/// Actions that can be performed on notes from widgets
public enum NoteWidgetAction: String, Codable, Equatable {
  /// Archive the note
  case archive
  /// Pin/unpin the note
  case pin
  /// Intent to create a new note (itemId will be empty)
  case addNew
}

// MARK: - Website Actions

/// Actions that can be performed on websites from widgets
public enum WebsiteWidgetAction: String, Codable, Equatable {
  /// Archive the website
  case archive
  /// Pin/unpin the website
  case pin
  /// Open the website in browser
  case open
}

// MARK: - File Actions

/// Actions that can be performed on files from widgets
public enum FileWidgetAction: String, Codable, Equatable {
  /// Pin/unpin the file
  case pin
  /// Open the file
  case open
}
