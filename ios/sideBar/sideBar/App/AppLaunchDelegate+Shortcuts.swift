#if os(iOS)
import UIKit
import Foundation
import sideBarShared

extension AppLaunchDelegate {

    struct ShortcutCategories {
        var file: [KeyboardShortcut] = []
        var edit: [KeyboardShortcut] = []
        var view: [KeyboardShortcut] = []
        var window: [KeyboardShortcut] = []
        var help: [KeyboardShortcut] = []
    }

    enum ShortcutMenuCategory {
        case file
        case edit
        case view
        case window
        case help
        case contextOnly
    }

    func categorizeShortcuts(
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

    func addShortcut(
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

    func categoryForUniversal(_ action: ShortcutAction) -> ShortcutMenuCategory {
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

    func categoryForContextual(_ action: ShortcutAction) -> ShortcutMenuCategory {
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
             .createFolder:
            return .edit
        case .navigateList:
            return .window
        default:
            return .contextOnly
        }
    }

    func imageForShortcut(_ shortcut: KeyboardShortcut) -> UIImage? {
        guard let appIcon = appIcon(for: shortcut) else { return nil }
        return UIImage(appIcon: appIcon)
    }

    func appIcon(for shortcut: KeyboardShortcut) -> AppIcon? {
        switch shortcut.action {
        case .navigate(let section):
            return Self.sectionIcons[section]
        case .navigateList(let direction):
            return Self.listDirectionIcons[direction]
        default:
            return Self.actionIcons[shortcut.action]
        }
    }

    func shortcutPayload(for shortcut: KeyboardShortcut) -> [String: String] {
        let action = shortcut.action
        var payload: [String: String] = [:]
        payload[ShortcutCommandKeys.commandId] = shortcut.id
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

    func shortcutAction(from payload: [String: String]) -> ShortcutAction? {
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

    static let sectionIcons: [AppSection: AppIcon] = [
        .notes: AppIcon.Domain.notes,
        .tasks: AppIcon.Domain.tasks,
        .websites: AppIcon.Domain.websites,
        .files: AppIcon.Domain.files,
        .skillsStore: AppIcon.Domain.skillsStore,
        .chat: AppIcon.Domain.chat,
        .settings: AppIcon.Settings.appPreferences
    ]

    static let listDirectionIcons: [ShortcutListDirection: AppIcon] = [
        .next: AppIcon.Navigation.nextItem,
        .previous: AppIcon.Navigation.previousItem
    ]

    static let actionIcons: [ShortcutAction: AppIcon] = [
        .openSettings: AppIcon.Settings.appPreferences,
        .newItem: AppIcon.Action.add,
        .closeItem: AppIcon.Action.close,
        .focusSearch: AppIcon.Action.search,
        .refreshSection: AppIcon.Action.refresh,
        .showShortcuts: AppIcon.Shortcut.showShortcuts,
        .openScratchpad: AppIcon.Content.scratchpad,
        .toggleSidebar: AppIcon.Shortcut.toggleSidebar,
        .sendMessage: AppIcon.Shortcut.sendMessage,
        .attachFile: AppIcon.Action.attach,
        .completeTask: AppIcon.State.successCircle,
        .editTaskNotes: AppIcon.Content.note,
        .moveTask: AppIcon.Shortcut.moveTask,
        .setTaskDueDate: AppIcon.Tasks.today,
        .setTaskRepeat: AppIcon.Tasks.recurrence,
        .renameItem: AppIcon.Action.rename,
        .deleteItem: AppIcon.Action.delete,
        .pinItem: AppIcon.Action.pin,
        .archiveItem: AppIcon.Action.archive,
        .openInBrowser: AppIcon.Shortcut.openInBrowser,
        .createFolder: AppIcon.Shortcut.createFolder,
        .openInDefaultApp: AppIcon.Action.openExternal,
        .quickLook: AppIcon.Skills.promptPreview
    ]

    static let commandTypeMap: [ShortcutAction: ShortcutCommandType] = [
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
        .createFolder: .createFolder,
        .openInDefaultApp: .openInDefaultApp,
        .quickLook: .quickLook
    ]

    static let actionFromCommandType: [ShortcutCommandType: ShortcutAction] = [
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
        .createFolder: .createFolder,
        .openInDefaultApp: .openInDefaultApp,
        .quickLook: .quickLook
    ]
}
#endif
