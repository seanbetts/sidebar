import Foundation

/// Represents a shortcut action event struct.
public struct ShortcutActionEvent: Identifiable {
    /// The id value.
    public let id: UUID
    /// The action value.
    public let action: ShortcutAction
    /// The section value.
    public let section: AppSection?
    /// The timestamp value.
    public let timestamp: Date

    public init(action: ShortcutAction, section: AppSection?) {
        self.id = UUID()
        self.action = action
        self.section = section
        self.timestamp = Date()
    }
}
