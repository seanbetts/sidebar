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
        case completeTask
        case editTaskNotes
        case moveTask
        case setTaskDueDate
        case setTaskRepeat
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
#endif
