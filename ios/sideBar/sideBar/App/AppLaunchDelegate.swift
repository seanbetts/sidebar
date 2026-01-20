import Foundation
import os

#if os(iOS)
import UIKit

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

    private func categorizeShortcuts(
        universal: [KeyboardShortcut],
        contextual: [KeyboardShortcut]
    ) -> (file: [KeyboardShortcut], edit: [KeyboardShortcut], view: [KeyboardShortcut], window: [KeyboardShortcut], help: [KeyboardShortcut], contextOnly: [KeyboardShortcut]) {
        var file: [KeyboardShortcut] = []
        var edit: [KeyboardShortcut] = []
        var view: [KeyboardShortcut] = []
        var window: [KeyboardShortcut] = []
        var help: [KeyboardShortcut] = []
        var contextOnly: [KeyboardShortcut] = []

        for shortcut in universal {
            switch shortcut.action {
            case .navigate:
                window.append(shortcut)
            case .newItem, .closeItem:
                file.append(shortcut)
            case .focusSearch:
                edit.append(shortcut)
            case .refreshSection, .openScratchpad, .toggleSidebar:
                view.append(shortcut)
            case .showShortcuts:
                help.append(shortcut)
            default:
                contextOnly.append(shortcut)
            }
        }

        for shortcut in contextual {
            switch shortcut.action {
            case .openInBrowser, .openInDefaultApp, .quickLook, .attachFile, .sendMessage:
                file.append(shortcut)
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
                edit.append(shortcut)
            case .navigateList:
                window.append(shortcut)
            default:
                contextOnly.append(shortcut)
            }
        }

        view.append(contentsOf: contextOnly)
        return (file, edit, view, window, help, [])
    }

    private func imageForShortcut(_ shortcut: KeyboardShortcut) -> UIImage? {
        guard let symbolName = symbolName(for: shortcut) else { return nil }
        return UIImage(systemName: symbolName)
    }

    private func symbolName(for shortcut: KeyboardShortcut) -> String? {
        switch shortcut.action {
        case .navigate(let section):
            switch section {
            case .notes:
                return "text.document"
            case .tasks:
                return "checkmark.square"
            case .websites:
                return "globe"
            case .files:
                return "folder"
            case .chat:
                return "bubble"
            case .settings:
                return "gearshape"
            }
        case .openSettings:
            return "gearshape"
        case .newItem:
            return "plus"
        case .closeItem:
            return "xmark"
        case .focusSearch:
            return "magnifyingglass"
        case .refreshSection:
            return "arrow.clockwise"
        case .showShortcuts:
            return "command"
        case .openScratchpad:
            return "square.and.pencil"
        case .toggleSidebar:
            return "sidebar.left"
        case .sendMessage:
            return "paperplane"
        case .attachFile:
            return "paperclip"
        case .renameItem:
            return "pencil"
        case .deleteItem:
            return "trash"
        case .pinItem:
            return "pin"
        case .archiveItem:
            return "archivebox"
        case .openInBrowser:
            return "safari"
        case .saveNote:
            return "square.and.arrow.down"
        case .toggleEditMode:
            return "square.and.pencil"
        case .formatBold:
            return "bold"
        case .formatItalic:
            return "italic"
        case .insertCodeBlock:
            return "chevron.left.slash.chevron.right"
        case .createFolder:
            return "folder.badge.plus"
        case .navigateList(let direction):
            return direction == .next ? "arrow.down" : "arrow.up"
        case .openInDefaultApp:
            return "arrow.up.right.square"
        case .quickLook:
            return "eye"
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
        case .openSettings:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.openSettings.rawValue
        case .newItem:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.newItem.rawValue
        case .closeItem:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.closeItem.rawValue
        case .focusSearch:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.focusSearch.rawValue
        case .refreshSection:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.refreshSection.rawValue
        case .showShortcuts:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.showShortcuts.rawValue
        case .openScratchpad:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.openScratchpad.rawValue
        case .toggleSidebar:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.toggleSidebar.rawValue
        case .sendMessage:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.sendMessage.rawValue
        case .attachFile:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.attachFile.rawValue
        case .renameItem:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.renameItem.rawValue
        case .deleteItem:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.deleteItem.rawValue
        case .pinItem:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.pinItem.rawValue
        case .archiveItem:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.archiveItem.rawValue
        case .openInBrowser:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.openInBrowser.rawValue
        case .saveNote:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.saveNote.rawValue
        case .toggleEditMode:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.toggleEditMode.rawValue
        case .formatBold:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.formatBold.rawValue
        case .formatItalic:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.formatItalic.rawValue
        case .insertCodeBlock:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.insertCodeBlock.rawValue
        case .createFolder:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.createFolder.rawValue
        case .openInDefaultApp:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.openInDefaultApp.rawValue
        case .quickLook:
            payload[ShortcutCommandKeys.type] = ShortcutCommandType.quickLook.rawValue
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
        case .openSettings:
            return .openSettings
        case .newItem:
            return .newItem
        case .closeItem:
            return .closeItem
        case .focusSearch:
            return .focusSearch
        case .refreshSection:
            return .refreshSection
        case .showShortcuts:
            return .showShortcuts
        case .openScratchpad:
            return .openScratchpad
        case .toggleSidebar:
            return .toggleSidebar
        case .sendMessage:
            return .sendMessage
        case .attachFile:
            return .attachFile
        case .renameItem:
            return .renameItem
        case .deleteItem:
            return .deleteItem
        case .pinItem:
            return .pinItem
        case .archiveItem:
            return .archiveItem
        case .openInBrowser:
            return .openInBrowser
        case .saveNote:
            return .saveNote
        case .toggleEditMode:
            return .toggleEditMode
        case .formatBold:
            return .formatBold
        case .formatItalic:
            return .formatItalic
        case .insertCodeBlock:
            return .insertCodeBlock
        case .createFolder:
            return .createFolder
        case .openInDefaultApp:
            return .openInDefaultApp
        case .quickLook:
            return .quickLook
        }
    }
}
#endif
