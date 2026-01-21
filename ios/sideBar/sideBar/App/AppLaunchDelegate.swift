import Foundation
import os

#if os(iOS)
import UIKit

// MARK: - AppLaunchDelegate

final class AppLaunchDelegate: UIResponder, UIApplicationDelegate {
    private enum ShortcutCommandKeys {
        static let type = "type"
        static let section = "section"
        static let direction = "direction"
    }

    private enum ShortcutCommandType: String {
        case navigate
        case openSettings
        case newItem
        case closeItem
        case focusSearch
        case refreshSection
        case showShortcuts
        case openScratchpad
        case toggleSidebar
        case sendMessage
        case attachFile
        case renameItem
        case deleteItem
        case pinItem
        case archiveItem
        case openInBrowser
        case saveNote
        case toggleEditMode
        case formatBold
        case formatItalic
        case insertCodeBlock
        case createFolder
        case navigateList
        case openInDefaultApp
        case quickLook
    }

    private let shortcutsFileIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.file")
    private let shortcutsEditIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.edit")
    private let shortcutsViewIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.view")
    private let shortcutsWindowIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.window")
    private let shortcutsHelpIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.help")
    private let shortcutsContextIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.context")
    private let router = ShortcutActionRouter()

    override init() {
        super.init()
        #if DEBUG
        AppLaunchMetrics.shared.mark("AppLaunchDelegate init")
        #endif
    }

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        AppLaunchMetrics.shared.mark("willFinishLaunching")
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        AppLaunchMetrics.shared.mark("didFinishLaunching")
        #endif
        return true
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        guard builder.system == .main else { return }

        builder.remove(menu: shortcutsFileIdentifier)
        builder.remove(menu: shortcutsEditIdentifier)
        builder.remove(menu: shortcutsViewIdentifier)
        builder.remove(menu: shortcutsWindowIdentifier)
        builder.remove(menu: shortcutsHelpIdentifier)
        builder.remove(menu: shortcutsContextIdentifier)

        let shortcuts = currentShortcuts()
        let universalShortcuts = shortcuts.filter { $0.contexts.contains(.universal) }
        let sectionShortcuts = shortcuts.filter { !$0.contexts.contains(.universal) }

        let categorized = categorizeShortcuts(
            universal: universalShortcuts,
            contextual: sectionShortcuts
        )

        if let fileMenu = makeMenu(identifier: shortcutsFileIdentifier, shortcuts: categorized.file) {
            builder.insertChild(fileMenu, atEndOfMenu: .file)
        }
        if let editMenu = makeMenu(identifier: shortcutsEditIdentifier, shortcuts: categorized.edit) {
            builder.insertChild(editMenu, atEndOfMenu: .edit)
        }
        if let viewMenu = makeMenu(identifier: shortcutsViewIdentifier, shortcuts: categorized.view) {
            builder.insertChild(viewMenu, atEndOfMenu: .view)
        }
        if let windowMenu = makeMenu(identifier: shortcutsWindowIdentifier, shortcuts: categorized.window) {
            if builder.menu(for: .window) != nil {
                builder.insertChild(windowMenu, atEndOfMenu: .window)
            } else {
                builder.insertChild(windowMenu, atEndOfMenu: .file)
            }
        }
        if let helpMenu = makeMenu(identifier: shortcutsHelpIdentifier, shortcuts: categorized.help) {
            builder.insertChild(helpMenu, atEndOfMenu: .help)
        }
    }

    @objc
    private func handleShortcut(_ sender: UIKeyCommand) {
        guard let payload = sender.propertyList as? [String: String],
              let action = shortcutAction(from: payload),
              let environment = AppEnvironment.shared else { return }
        Task { @MainActor in
            router.handle(action, environment: environment)
        }
    }

    private func currentContexts() -> Set<ShortcutContext> {
        AppEnvironment.shared?.activeShortcutContexts ?? [.universal]
    }

    private func currentShortcuts() -> [KeyboardShortcut] {
        KeyboardShortcutRegistry.shared.shortcuts(for: currentContexts())
            .filter { $0.action != .openSettings }
    }

    private func currentSectionTitle() -> String {
        AppEnvironment.shared?.activeSection?.title ?? "Section"
    }

    private func makeMenu(identifier: UIMenu.Identifier, shortcuts: [KeyboardShortcut]) -> UIMenu? {
        guard !shortcuts.isEmpty else { return nil }
        let commands = shortcuts.map { shortcut -> UIKeyCommand in
            let payload = shortcutPayload(for: shortcut.action)
            let command = UIKeyCommand(
                title: shortcut.title,
                image: imageForShortcut(shortcut),
                action: #selector(handleShortcut(_:)),
                input: shortcut.input,
                modifierFlags: shortcut.modifiers,
                propertyList: payload
            )
            command.discoverabilityTitle = shortcut.description
            return command
        }
        return UIMenu(title: "", image: nil, identifier: identifier, options: .displayInline, children: commands)
    }
}

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
