import Foundation

public struct ShortcutActionEvent: Identifiable {
    public let id: UUID
    public let action: ShortcutAction
    public let section: AppSection?
    public let timestamp: Date

    public init(action: ShortcutAction, section: AppSection?) {
        self.id = UUID()
        self.action = action
        self.section = section
        self.timestamp = Date()
    }
}
