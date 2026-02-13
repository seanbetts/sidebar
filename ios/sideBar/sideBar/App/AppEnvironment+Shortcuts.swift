#if os(iOS) || os(macOS)
import Foundation

extension AppEnvironment {
    public var activeShortcutContexts: Set<ShortcutContext> {
        var contexts: Set<ShortcutContext> = [.universal]
        let section = focusedSection ?? activeSection
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
        shortcutActionEvent = ShortcutActionEvent(action: action, section: focusedSection ?? activeSection)
    }
}
#endif
