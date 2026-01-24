#if os(iOS)
import Foundation

extension AppEnvironment {
    public var activeShortcutContexts: Set<ShortcutContext> {
        var contexts: Set<ShortcutContext> = [.universal]
        if let activeSection {
            if activeSection == .tasks {
                if isTasksFocused {
                    contexts.insert(.tasks)
                }
            } else {
                contexts.insert(ShortcutContext.from(section: activeSection))
            }
        }
        if isNotesEditing {
            contexts.insert(.notesEditing)
        }
        return contexts
    }

    public func emitShortcutAction(_ action: ShortcutAction) {
        shortcutActionEvent = ShortcutActionEvent(action: action, section: activeSection)
    }
}
#endif
