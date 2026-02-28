import Foundation

/// Represents a shortcut action event struct.
public struct ShortcutActionEvent: Identifiable {
    /// The id value.
    public let id: UUID
    /// The action value.
    public let action: ShortcutAction
    /// The section value.
    public let section: AppSection?
    /// The pane value.
    public let pane: WorkspacePane?
    /// The timestamp value.
    public let timestamp: Date

    public init(
        action: ShortcutAction,
        section: AppSection?,
        pane: WorkspacePane? = nil
    ) {
        self.id = UUID()
        self.action = action
        self.section = section
        self.pane = pane
        self.timestamp = Date()
    }
}

extension ShortcutActionEvent {
    func matches(section: AppSection, workspacePane: WorkspacePane) -> Bool {
        guard self.section == section else { return false }
        return pane == nil || pane == workspacePane
    }
}
