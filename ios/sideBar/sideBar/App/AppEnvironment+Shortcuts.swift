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
        shortcutActionEvent = ShortcutActionEvent(action: action, section: shortcutResolutionSection)
    }
}
#endif
