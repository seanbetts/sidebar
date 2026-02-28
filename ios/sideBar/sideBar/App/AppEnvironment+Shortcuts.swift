#if os(iOS) || os(macOS)
import Foundation

extension AppEnvironment {
    private var shortcutResolutionSection: AppSection? {
        #if os(macOS)
        focusedSection ?? activeSection
        #else
        activeSection ?? focusedSection
        #endif
    }

    private var shortcutResolutionPane: WorkspacePane? {
        resolveShortcutPane(
            section: shortcutResolutionSection,
            focusedPane: focusedWorkspacePane,
            workspaceState: workspaceStore.state
        )
    }

    private func resolveShortcutPane(
        section: AppSection?,
        focusedPane: WorkspacePane?,
        workspaceState: WorkspaceState
    ) -> WorkspacePane? {
        guard let targetSection = section else {
            return focusedPane
        }

        if let focusedPane, paneSection(in: focusedPane, state: workspaceState) == targetSection {
            return focusedPane
        }
        if paneSection(in: .primary, state: workspaceState) == targetSection {
            return .primary
        }
        if paneSection(in: .secondary, state: workspaceState) == targetSection {
            return .secondary
        }
        return focusedPane
    }

    private func paneSection(
        in pane: WorkspacePane,
        state: WorkspaceState
    ) -> AppSection? {
        switch pane {
        case .primary:
            return WorkspaceLegacySectionAdapter.section(from: state.primaryPane.descriptor)
        case .secondary:
            guard state.layout != .compact,
                  let secondaryPane = state.secondaryPane else {
                return nil
            }
            return WorkspaceLegacySectionAdapter.section(from: secondaryPane.descriptor)
        }
    }

    public var activeShortcutContexts: Set<ShortcutContext> {
        var contexts: Set<ShortcutContext> = [.universal]
        let section = shortcutResolutionSection
        if let section {
            if section == .tasks {
                if focusedSection == .tasks || isTasksFocused {
                    contexts.insert(.tasks)
                }
            } else {
                contexts.insert(ShortcutContext.from(section: section))
            }
        }
        return contexts
    }

    public func emitShortcutAction(_ action: ShortcutAction) {
        let event = ShortcutActionEvent(
            action: action,
            section: shortcutResolutionSection,
            pane: shortcutResolutionPane
        )
        shortcutActionEvent = event

        // Treat shortcut events as one-shot broadcasts so stale events are not replayed
        // to views that subscribe later (for example when switching sections).
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.shortcutActionEvent?.id == event.id else { return }
            self?.shortcutActionEvent = nil
        }
    }
}
#endif
