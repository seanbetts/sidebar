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
            logger.warning(
                "Shortcut conflict for \(signature, privacy: .public): " +
                    "\(titles.joined(separator: ", "), privacy: .public) " +
                    "contexts: \(contexts.joined(separator: ", "), privacy: .public)"
            )
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

extension KeyboardShortcutRegistry {
    private static func buildShortcuts() -> [KeyboardShortcut] {
        buildUniversalShortcuts()
            + buildChatShortcuts()
            + buildNotesShortcuts()
            + buildNotesEditingShortcuts()
            + buildWebsitesShortcuts()
            + buildFilesShortcuts()
            + buildTasksShortcuts()
    }

    private static func buildUniversalShortcuts() -> [KeyboardShortcut] {
        [
            KeyboardShortcut(
                input: "1",
                title: "Notes",
                description: "Navigate to Notes",
                action: .navigate(.notes),
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "2",
                title: "Tasks",
                description: "Navigate to Tasks",
                action: .navigate(.tasks),
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "3",
                title: "Websites",
                description: "Navigate to Websites",
                action: .navigate(.websites),
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "4",
                title: "Files",
                description: "Navigate to Files",
                action: .navigate(.files),
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "5",
                title: "Chat",
                description: "Navigate to Chat",
                action: .navigate(.chat),
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: ",",
                title: "Settings",
                description: "Open Settings",
                action: .openSettings,
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "n",
                title: "New",
                description: "Create a new item in the current section",
                action: .newItem,
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "f",
                title: "Search",
                description: "Focus search in the current section",
                action: .focusSearch,
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "w",
                title: "Close",
                description: "Close the current item",
                action: .closeItem,
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "r",
                title: "Refresh",
                description: "Refresh the current section",
                action: .refreshSection,
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "/",
                modifiers: [.command, .shift],
                title: "Keyboard Shortcuts",
                description: "Show keyboard shortcuts reference",
                action: .showShortcuts,
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "o",
                modifiers: [.command, .shift],
                title: "Scratchpad",
                description: "Open scratchpad",
                action: .openScratchpad,
                contexts: [.universal]
            ),
            KeyboardShortcut(
                input: "s",
                modifiers: [.command, .shift],
                title: "Toggle Sidebar",
                description: "Show or hide the sidebar",
                action: .toggleSidebar,
                contexts: [.universal]
            )
        ]
    }

    private static func buildChatShortcuts() -> [KeyboardShortcut] {
        [
            KeyboardShortcut(
                input: "\r",
                modifiers: [.command],
                title: "Send Message",
                description: "Send the current chat message",
                action: .sendMessage,
                contexts: [.chat]
            ),
            KeyboardShortcut(
                input: "f",
                modifiers: [.command, .shift],
                title: "Attach File",
                description: "Attach a file to the chat",
                action: .attachFile,
                contexts: [.chat]
            ),
            KeyboardShortcut(
                input: "r",
                modifiers: [.command, .shift],
                title: "Rename Conversation",
                description: "Rename the current conversation",
                action: .renameItem,
                contexts: [.chat]
            ),
            KeyboardShortcut(
                input: UIKeyCommand.inputDelete,
                modifiers: [.command],
                title: "Delete Conversation",
                description: "Delete the current conversation",
                action: .deleteItem,
                contexts: [.chat]
            )
        ]
    }

    private static func buildNotesShortcuts() -> [KeyboardShortcut] {
        [
            KeyboardShortcut(
                input: "n",
                modifiers: [.command, .shift],
                title: "New Folder",
                description: "Create a new folder",
                action: .createFolder,
                contexts: [.notes]
            ),
            KeyboardShortcut(
                input: "e",
                title: "Toggle Edit",
                description: "Toggle between edit and preview",
                action: .toggleEditMode,
                contexts: [.notes]
            ),
            KeyboardShortcut(
                input: "p",
                modifiers: [.command, .shift],
                title: "Pin Note",
                description: "Pin or unpin the current note",
                action: .pinItem,
                contexts: [.notes]
            ),
            KeyboardShortcut(
                input: "a",
                modifiers: [.command, .shift],
                title: "Archive Note",
                description: "Archive or unarchive the current note",
                action: .archiveItem,
                contexts: [.notes]
            ),
            KeyboardShortcut(
                input: "r",
                modifiers: [.command, .alternate],
                title: "Rename Note",
                description: "Rename the current note",
                action: .renameItem,
                contexts: [.notes]
            ),
            KeyboardShortcut(
                input: UIKeyCommand.inputDelete,
                modifiers: [.command, .shift],
                title: "Delete Note",
                description: "Delete the current note",
                action: .deleteItem,
                contexts: [.notes]
            )
        ]
    }

    private static func buildNotesEditingShortcuts() -> [KeyboardShortcut] {
        [
            KeyboardShortcut(
                input: "b",
                title: "Bold",
                description: "Apply bold formatting",
                action: .formatBold,
                contexts: [.notesEditing]
            ),
            KeyboardShortcut(
                input: "i",
                title: "Italic",
                description: "Apply italic formatting",
                action: .formatItalic,
                contexts: [.notesEditing]
            ),
            KeyboardShortcut(
                input: "k",
                modifiers: [.command, .shift],
                title: "Code Block",
                description: "Insert a code block",
                action: .insertCodeBlock,
                contexts: [.notesEditing]
            )
        ]
    }

    private static func buildWebsitesShortcuts() -> [KeyboardShortcut] {
        [
            KeyboardShortcut(
                input: "p",
                modifiers: [.command, .alternate],
                title: "Pin Website",
                description: "Pin or unpin the current website",
                action: .pinItem,
                contexts: [.websites]
            ),
            KeyboardShortcut(
                input: "a",
                modifiers: [.command, .alternate],
                title: "Archive Website",
                description: "Archive or unarchive the current website",
                action: .archiveItem,
                contexts: [.websites]
            ),
            KeyboardShortcut(
                input: UIKeyCommand.inputDelete,
                modifiers: [.command, .alternate],
                title: "Delete Website",
                description: "Delete the current website",
                action: .deleteItem,
                contexts: [.websites]
            ),
            KeyboardShortcut(
                input: "\r",
                modifiers: [.command, .shift],
                title: "Open in Browser",
                description: "Open the website in the browser",
                action: .openInBrowser,
                contexts: [.websites]
            )
        ]
    }

    private static func buildFilesShortcuts() -> [KeyboardShortcut] {
        [
            KeyboardShortcut(
                input: UIKeyCommand.inputDelete,
                modifiers: [.command, .alternate, .shift],
                title: "Delete File",
                description: "Delete the current file",
                action: .deleteItem,
                contexts: [.files]
            ),
            KeyboardShortcut(
                input: " ",
                title: "Quick Look",
                description: "Preview the current file",
                action: .quickLook,
                contexts: [.files]
            )
        ]
    }

    private static func buildTasksShortcuts() -> [KeyboardShortcut] {
        [
            KeyboardShortcut(
                input: "\r",
                title: "Complete Task",
                description: "Mark the selected task as complete",
                action: .completeTask,
                contexts: [.tasks]
            ),
            KeyboardShortcut(
                input: "n",
                modifiers: [.command, .shift],
                title: "Edit Notes",
                description: "Open the notes editor for the selected task",
                action: .editTaskNotes,
                contexts: [.tasks]
            ),
            KeyboardShortcut(
                input: "m",
                modifiers: [.command, .shift],
                title: "Move Task",
                description: "Move the selected task to another group or project",
                action: .moveTask,
                contexts: [.tasks]
            ),
            KeyboardShortcut(
                input: "d",
                title: "Set Due Date",
                description: "Adjust the due date for the selected task",
                action: .setTaskDueDate,
                contexts: [.tasks]
            ),
            KeyboardShortcut(
                input: "r",
                modifiers: [.command, .shift],
                title: "Edit Repeat",
                description: "Adjust repeat settings for the selected task",
                action: .setTaskRepeat,
                contexts: [.tasks]
            ),
            KeyboardShortcut(
                input: UIKeyCommand.inputDelete,
                modifiers: [.command, .shift],
                title: "Delete Task",
                description: "Delete the selected task",
                action: .deleteItem,
                contexts: [.tasks]
            )
        ]
    }
}
#endif
