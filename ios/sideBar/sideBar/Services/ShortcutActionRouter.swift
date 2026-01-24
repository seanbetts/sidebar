#if os(iOS)
import Foundation

@MainActor
/// Routes shortcut actions to view models.
public final class ShortcutActionRouter {
    public init() {}

    public func handle(_ shortcut: KeyboardShortcut, environment: AppEnvironment) {
        handle(shortcut.action, environment: environment)
    }

    public func handle(_ action: ShortcutAction, environment: AppEnvironment) {
        let section = environment.activeSection
        if handleNavigation(action, environment: environment) {
            return
        }
        if handleSectionAction(action, section: section, environment: environment) {
            return
        }
        environment.emitShortcutAction(action)
    }

    private func handleNavigation(_ action: ShortcutAction, environment: AppEnvironment) -> Bool {
        switch action {
        case .navigate(let target):
            environment.commandSelection = target
            return true
        case .openSettings:
            environment.commandSelection = .settings
            return true
        default:
            return false
        }
    }

    private func handleSectionAction(
        _ action: ShortcutAction,
        section: AppSection?,
        environment: AppEnvironment
    ) -> Bool {
        switch action {
        case .newItem:
            handleNewItem(section: section, environment: environment)
            return true
        case .closeItem:
            handleCloseItem(section: section, environment: environment)
            return true
        case .refreshSection:
            handleRefresh(section: section, environment: environment)
            return true
        case .pinItem:
            handlePinToggle(section: section, environment: environment)
            return true
        default:
            return false
        }
    }

    private func handleNewItem(section: AppSection?, environment: AppEnvironment) {
        switch section {
        case .chat:
            Task { await environment.chatViewModel.startNewConversation() }
        case .notes, .websites, .files:
            environment.emitShortcutAction(.newItem)
        case .tasks:
            environment.tasksViewModel.startNewTask()
        case .settings, .none:
            break
        }
    }

    private func handleCloseItem(section: AppSection?, environment: AppEnvironment) {
        switch section {
        case .chat:
            Task { await environment.chatViewModel.closeConversation() }
        case .notes:
            environment.notesViewModel.clearSelection()
        case .websites:
            environment.websitesViewModel.clearSelection()
        case .files:
            environment.ingestionViewModel.clearSelection()
        case .tasks, .settings, .none:
            break
        }
    }

    private func handleRefresh(section: AppSection?, environment: AppEnvironment) {
        switch section {
        case .chat:
            Task { await environment.chatViewModel.loadConversations() }
        case .notes:
            Task { await environment.notesViewModel.loadTree() }
        case .websites:
            Task { await environment.websitesViewModel.load(force: true) }
        case .files:
            Task { await environment.ingestionViewModel.load() }
        case .tasks:
            Task { await environment.tasksViewModel.load(selection: environment.tasksViewModel.selection, force: true) }
            Task { await environment.tasksViewModel.loadCounts(force: true) }
        case .settings, .none:
            break
        }
    }

    private func handlePinToggle(section: AppSection?, environment: AppEnvironment) {
        switch section {
        case .notes:
            guard let noteId = environment.notesViewModel.selectedNoteId else { return }
            let isPinned = environment.notesViewModel.noteNode(id: noteId)?.pinned == true
            Task { await environment.notesViewModel.setPinned(id: noteId, pinned: !isPinned) }
        case .websites:
            guard let website = environment.websitesViewModel.active else { return }
            Task { await environment.websitesViewModel.setPinned(id: website.id, pinned: !website.pinned) }
        case .files:
            guard let fileId = environment.ingestionViewModel.selectedFileId,
                  let item = environment.ingestionViewModel.items.first(where: { $0.file.id == fileId }) else { return }
            let pinned = item.file.pinned ?? false
            Task { await environment.ingestionViewModel.togglePinned(fileId: fileId, pinned: !pinned) }
        case .chat, .tasks, .settings, .none:
            break
        }
    }

}
#endif
