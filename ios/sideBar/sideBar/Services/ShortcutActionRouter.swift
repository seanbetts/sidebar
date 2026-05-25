#if os(iOS)
import Foundation

/// Routes shortcut actions to view models.
@MainActor public final class ShortcutActionRouter {
    public init() {}

    public func handle(_ shortcut: KeyboardShortcut, environment: AppEnvironment) {
        handle(shortcut.action, environment: environment)
    }

    public func handle(_ action: ShortcutAction, environment: AppEnvironment) {
        let section = environment.activeSection ?? environment.focusedSection
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
            environment.routeWorkspaceSelection(
                to: target,
                source: "shortcut_navigate"
            )
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
        case .skillsStore, .settings, .none:
            break
        }
    }

    private func handleCloseItem(section: AppSection?, environment: AppEnvironment) {
        switch section {
        case .chat:
            Task { await environment.chatViewModel.closeConversation() }
        case .notes:
            environment.emitShortcutAction(.closeItem)
        case .websites:
            environment.websitesViewModel.clearSelection()
        case .files:
            environment.ingestionViewModel.clearSelection()
        case .tasks, .skillsStore, .settings, .none:
            break
        }
    }

    private func handleRefresh(section: AppSection?, environment: AppEnvironment) {
        switch section {
        case .chat:
            Task { await environment.chatViewModel.loadConversations() }
        case .notes:
            Task { await environment.notesRuntime.viewModel.loadTree() }
        case .websites:
            Task { await environment.websitesViewModel.load(force: true) }
        case .files:
            Task { await environment.ingestionViewModel.load() }
        case .tasks:
            Task { await environment.tasksViewModel.load(selection: environment.tasksViewModel.selection, force: true) }
            Task { await environment.tasksViewModel.loadCounts(force: true) }
        case .skillsStore:
            Task { await environment.settingsViewModel.loadSkills() }
        case .settings, .none:
            break
        }
    }

    private func handlePinToggle(section: AppSection?, environment: AppEnvironment) {
        switch section {
        case .notes:
            guard let noteId = environment.notesRuntime.viewModel.selectedNoteId else { return }
            let isPinned = environment.notesRuntime.viewModel.noteNode(id: noteId)?.pinned == true
            Task { await environment.notesRuntime.viewModel.setPinned(id: noteId, pinned: !isPinned) }
        case .websites:
            guard let website = environment.websitesViewModel.active else { return }
            Task { await environment.websitesViewModel.setPinned(id: website.id, pinned: !website.pinned) }
        case .files:
            guard let fileId = environment.ingestionViewModel.selectedFileId,
                  let item = environment.ingestionViewModel.items.first(where: { $0.file.id == fileId }) else { return }
            let pinned = item.file.pinned ?? false
            Task { await environment.ingestionViewModel.togglePinned(fileId: fileId, pinned: !pinned) }
        case .chat, .tasks, .skillsStore, .settings, .none:
            break
        }
    }

}
#endif
