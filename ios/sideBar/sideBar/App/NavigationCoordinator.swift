import Combine
import Foundation

@MainActor
/// Central coordinator for cross-feature navigation and deep-link state.
public final class NavigationCoordinator: ObservableObject {
    @Published public var commandSelection: AppSection?
    @Published public var activeSection: AppSection?
    @Published public var isTasksFocused: Bool = false
    @Published public var pendingNewTaskDeepLink: Bool = false
    @Published public var pendingNewNoteDeepLink: Bool = false
    @Published public var pendingScratchpadDeepLink: Bool = false
    @Published public var shortcutActionEvent: ShortcutActionEvent?
    @Published public var tasksPhoneDetailRouteId: String?

    public init() {
    }

    public func resetForSignOut() {
        commandSelection = nil
        activeSection = nil
        isTasksFocused = false
        pendingNewTaskDeepLink = false
        pendingNewNoteDeepLink = false
        pendingScratchpadDeepLink = false
        shortcutActionEvent = nil
        tasksPhoneDetailRouteId = nil
    }
}
