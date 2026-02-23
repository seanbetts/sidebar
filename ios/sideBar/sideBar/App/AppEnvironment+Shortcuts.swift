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
        let event = ShortcutActionEvent(action: action, section: shortcutResolutionSection)
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
