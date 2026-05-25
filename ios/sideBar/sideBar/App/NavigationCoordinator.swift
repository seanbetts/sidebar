import Combine
import Foundation

/// Central coordinator for cross-feature navigation and deep-link state.
@MainActor public final class NavigationCoordinator: ObservableObject {
    @Published public var commandSelection: AppSection?
    @Published public var activeSection: AppSection?
    @Published public var focusedSection: AppSection?
    @Published public var focusedWorkspacePane: WorkspacePane?
    @Published public var isTasksFocused: Bool = false
    @Published public var pendingSidebarDeepLink: URL?
    @Published public var shortcutActionEvent: ShortcutActionEvent?
    @Published public var notesPhoneDetailRouteId: String?
    @Published public var tasksPhoneDetailRouteId: String?

    public init() {
    }

    public func resetForSignOut() {
        commandSelection = nil
        activeSection = nil
        focusedSection = nil
        focusedWorkspacePane = nil
        isTasksFocused = false
        pendingSidebarDeepLink = nil
        shortcutActionEvent = nil
        notesPhoneDetailRouteId = nil
        tasksPhoneDetailRouteId = nil
    }
}
