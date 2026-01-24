#if os(iOS)
import UIKit
import os

// MARK: - KeyboardShortcutRegistry

/// Registers and resolves keyboard shortcuts.
public final class KeyboardShortcutRegistry {
    public static let shared = KeyboardShortcutRegistry()

    public let allShortcuts: [KeyboardShortcut]
    private let logger = Logger(subsystem: "sideBar", category: "KeyboardShortcuts")

    private init() {
        self.allShortcuts = Self.buildShortcuts()
        logConflicts()
    }

    public func shortcuts(for contexts: Set<ShortcutContext>) -> [KeyboardShortcut] {
        let candidates = allShortcuts.filter { !contexts.isDisjoint(with: $0.contexts) }
        let prioritized = candidates.sorted { lhs, rhs in
            priorityScore(for: lhs, contexts: contexts) > priorityScore(for: rhs, contexts: contexts)
        }
        var seen = Set<String>()
        var resolved: [KeyboardShortcut] = []
        for shortcut in prioritized {
            let signature = shortcut.keySignature
            guard !seen.contains(signature) else { continue }
            seen.insert(signature)
            resolved.append(shortcut)
        }
        return resolved
    }

    public func groupedShortcuts() -> [ShortcutContext: [KeyboardShortcut]] {
        var grouped: [ShortcutContext: [KeyboardShortcut]] = [:]
        for context in ShortcutContext.allCases {
            let shortcuts = allShortcuts.filter { $0.contexts.contains(context) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            if !shortcuts.isEmpty {
                grouped[context] = shortcuts
            }
        }
        return grouped
    }

    private func priorityScore(for shortcut: KeyboardShortcut, contexts: Set<ShortcutContext>) -> Int {
        let priorities: [ShortcutContext: Int] = [
            .notesEditing: 6,
            .chat: 5,
            .notes: 4,
            .websites: 3,
            .files: 3,
            .tasks: 2,
            .universal: 1
        ]
        return shortcut.contexts
            .filter { contexts.contains($0) }
            .map { priorities[$0] ?? 0 }
            .max() ?? 0
    }

    private func logConflicts() {
        #if DEBUG
        var buckets: [String: [KeyboardShortcut]] = [:]
        for shortcut in allShortcuts {
            buckets[shortcut.keySignature, default: []].append(shortcut)
        }
        for (signature, shortcuts) in buckets where shortcuts.count > 1 {
            guard hasContextOverlap(shortcuts) else { continue }
            let contexts = shortcuts.flatMap { $0.contexts.map { $0.rawValue } }.sorted()
            let titles = shortcuts.map { $0.title }.sorted()
            let message = "Shortcut conflict for \(signature): " +
                "\(titles.joined(separator: ", ")) contexts: \(contexts.joined(separator: ", "))"
            logger.warning("\(message, privacy: .public)")
        }
        #endif
    }

    private func hasContextOverlap(_ shortcuts: [KeyboardShortcut]) -> Bool {
        for index in shortcuts.indices {
            for otherIndex in shortcuts.indices where otherIndex > index {
                let lhs = shortcuts[index].contexts
                let rhs = shortcuts[otherIndex].contexts
                if lhs.contains(.universal) || rhs.contains(.universal) {
                    return true
                }
                if !lhs.isDisjoint(with: rhs) {
                    return true
                }
            }
        }
        return false
    }
}
#endif
