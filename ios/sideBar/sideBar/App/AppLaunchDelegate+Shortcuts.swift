#if os(iOS)
import UIKit
import Foundation

extension AppLaunchDelegate {

    private struct ShortcutCategories {
        var file: [KeyboardShortcut] = []
        var edit: [KeyboardShortcut] = []
        var view: [KeyboardShortcut] = []
        var window: [KeyboardShortcut] = []
        var help: [KeyboardShortcut] = []
    }

    private enum ShortcutMenuCategory {
        case file
        case edit
        case view
        case window
        case help
        case contextOnly
    }

    private func categorizeShortcuts(
        universal: [KeyboardShortcut],
        contextual: [KeyboardShortcut]
    ) -> ShortcutCategories {
        var categories = ShortcutCategories()
        var contextOnly: [KeyboardShortcut] = []

        for shortcut in universal {
            addShortcut(
                shortcut,
                category: categoryForUniversal(shortcut.action),
                categories: &categories,
                contextOnly: &contextOnly
            )
        }

        for shortcut in contextual {
            addShortcut(
                shortcut,
                category: categoryForContextual(shortcut.action),
                categories: &categories,
                contextOnly: &contextOnly
            )
        }

        categories.view.append(contentsOf: contextOnly)
        return categories
    }

    private func addShortcut(
        _ shortcut: KeyboardShortcut,
        category: ShortcutMenuCategory,
        categories: inout ShortcutCategories,
        contextOnly: inout [KeyboardShortcut]
    ) {
        switch category {
        case .file:
            categories.file.append(shortcut)
        case .edit:
            categories.edit.append(shortcut)
        case .view:
            categories.view.append(shortcut)
        case .window:
            categories.window.append(shortcut)
        case .help:
            categories.help.append(shortcut)
        case .contextOnly:
            contextOnly.append(shortcut)
        }
    }

    private func categoryForUniversal(_ action: ShortcutAction) -> ShortcutMenuCategory {
        switch action {
        case .navigate:
            return .window
        case .newItem, .closeItem:
            return .file
        case .focusSearch:
            return .edit
        case .refreshSection, .openScratchpad, .toggleSidebar:
            return .view
        case .showShortcuts:
            return .help
        default:
            return .contextOnly
        }
    }

    private func categoryForContextual(_ action: ShortcutAction) -> ShortcutMenuCategory {
        switch action {
        case .openInBrowser, .openInDefaultApp, .quickLook, .attachFile, .sendMessage:
            return .file
        case .renameItem,
             .completeTask,
             .editTaskNotes,
             .moveTask,
             .setTaskDueDate,
             .setTaskRepeat,
             .deleteItem,
             .archiveItem,
             .pinItem,
             .saveNote,
             .toggleEditMode,
             .formatBold,
             .formatItalic,
             .insertCodeBlock,
             .createFolder:
            return .edit
        case .navigateList:
            return .window
        default:
            return .contextOnly
        }
    }

    private func imageForShortcut(_ shortcut: KeyboardShortcut) -> UIImage? {
        guard let symbolName = symbolName(for: shortcut) else { return nil }
        return UIImage(systemName: symbolName)
    }

    private func symbolName(for shortcut: KeyboardShortcut) -> String? {
        switch shortcut.action {
        case .navigate(let section):
            return Self.sectionSymbolNames[section]
        case .navigateList(let direction):
            return Self.listDirectionSymbols[direction]
        default:
            return Self.actionSymbolNames[shortcut.action]
        }
    }

    private func shortcutPayload(for action: ShortcutAction) -> [String: String] {
        var payload: [String: String] = [:]
        switch action {
        case .navigate(let section):
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.navigate.rawValue
            payload[ShortcutCommandKeys.section] = section.rawValue
        case .navigateList(let direction):
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.navigateList.rawValue
            payload[ShortcutCommandKeys.direction] = direction.rawValue
        default:
            guard let commandType = Self.commandTypeMap[action] else {
                return payload
            }
            payload[ShortcutCommandKeys.type] = commandType.rawValue
        }
        return payload
    }

    private func shortcutAction(from payload: [String: String]) -> ShortcutAction? {
        guard let typeRaw = payload[ShortcutCommandKeys.type],
              let type = ShortcutCommandType(rawValue: typeRaw) else { return nil }
        switch type {
        case .navigate:
            guard let sectionRaw = payload[ShortcutCommandKeys.section],
                  let section = AppSection(rawValue: sectionRaw) else { return nil }
            return .navigate(section)
        case .navigateList:
            guard let directionRaw = payload[ShortcutCommandKeys.direction],
                  let direction = ShortcutListDirection(rawValue: directionRaw) else { return nil }
            return .navigateList(direction)
        default:
            return Self.actionFromCommandType[type]
        }
    }

    private static let sectionSymbolNames: [AppSection: String] = [
        .notes: "text.document",
        .tasks: "checkmark.square",
        .websites: "globe",
        .files: "folder",
        .chat: "bubble",
        .settings: "gearshape"
    ]

    private static let listDirectionSymbols: [ShortcutListDirection: String] = [
        .next: "arrow.down",
        .previous: "arrow.up"
    ]

    private static let actionSymbolNames: [ShortcutAction: String] = [
        .openSettings: "gearshape",
        .newItem: "plus",
        .closeItem: "xmark",
        .focusSearch: "magnifyingglass",
        .refreshSection: "arrow.clockwise",
        .showShortcuts: "command",
        .openScratchpad: "square.and.pencil",
        .toggleSidebar: "sidebar.left",
        .sendMessage: "paperplane",
        .attachFile: "paperclip",
        .completeTask: "checkmark.circle",
        .editTaskNotes: "note.text",
        .moveTask: "arrowshape.turn.up.right",
        .setTaskDueDate: "calendar",
        .setTaskRepeat: "repeat",
        .renameItem: "pencil",
        .deleteItem: "trash",
        .pinItem: "pin",
        .archiveItem: "archivebox",
        .openInBrowser: "safari",
        .saveNote: "square.and.arrow.down",
        .toggleEditMode: "square.and.pencil",
        .formatBold: "bold",
        .formatItalic: "italic",
        .insertCodeBlock: "chevron.left.slash.chevron.right",
        .createFolder: "folder.badge.plus",
        .openInDefaultApp: "arrow.up.right.square",
        .quickLook: "eye"
    ]

    private static let commandTypeMap: [ShortcutAction: ShortcutCommandType] = [
        .openSettings: .openSettings,
        .newItem: .newItem,
        .closeItem: .closeItem,
        .focusSearch: .focusSearch,
        .refreshSection: .refreshSection,
        .showShortcuts: .showShortcuts,
        .openScratchpad: .openScratchpad,
        .toggleSidebar: .toggleSidebar,
        .sendMessage: .sendMessage,
        .attachFile: .attachFile,
        .completeTask: .completeTask,
        .editTaskNotes: .editTaskNotes,
        .moveTask: .moveTask,
        .setTaskDueDate: .setTaskDueDate,
        .setTaskRepeat: .setTaskRepeat,
        .renameItem: .renameItem,
        .deleteItem: .deleteItem,
        .pinItem: .pinItem,
        .archiveItem: .archiveItem,
        .openInBrowser: .openInBrowser,
        .saveNote: .saveNote,
        .toggleEditMode: .toggleEditMode,
        .formatBold: .formatBold,
        .formatItalic: .formatItalic,
        .insertCodeBlock: .insertCodeBlock,
        .createFolder: .createFolder,
        .openInDefaultApp: .openInDefaultApp,
        .quickLook: .quickLook
    ]

    private static let actionFromCommandType: [ShortcutCommandType: ShortcutAction] = [
        .openSettings: .openSettings,
        .newItem: .newItem,
        .closeItem: .closeItem,
        .focusSearch: .focusSearch,
        .refreshSection: .refreshSection,
        .showShortcuts: .showShortcuts,
        .openScratchpad: .openScratchpad,
        .toggleSidebar: .toggleSidebar,
        .sendMessage: .sendMessage,
        .attachFile: .attachFile,
        .completeTask: .completeTask,
        .editTaskNotes: .editTaskNotes,
        .moveTask: .moveTask,
        .setTaskDueDate: .setTaskDueDate,
        .setTaskRepeat: .setTaskRepeat,
        .renameItem: .renameItem,
        .deleteItem: .deleteItem,
        .pinItem: .pinItem,
        .archiveItem: .archiveItem,
        .openInBrowser: .openInBrowser,
        .saveNote: .saveNote,
        .toggleEditMode: .toggleEditMode,
        .formatBold: .formatBold,
        .formatItalic: .formatItalic,
        .insertCodeBlock: .insertCodeBlock,
        .createFolder: .createFolder,
        .openInDefaultApp: .openInDefaultApp,
        .quickLook: .quickLook
    ]
}
#endif
