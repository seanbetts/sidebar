#if os(iOS)
import SwiftUI
import UIKit

struct KeyboardShortcutHandler: UIViewControllerRepresentable {
    @EnvironmentObject private var environment: AppEnvironment
    private let registry = KeyboardShortcutRegistry.shared
    private let router = ShortcutActionRouter()

    func makeUIViewController(context: Context) -> KeyCommandController {
        let controller = KeyCommandController()
        controller.onShortcut = handleShortcut
        controller.updateShortcuts(registry.shortcuts(for: environment.activeShortcutContexts))
        return controller
    }

    func updateUIViewController(_ uiViewController: KeyCommandController, context: Context) {
        uiViewController.onShortcut = handleShortcut
        uiViewController.updateShortcuts(registry.shortcuts(for: environment.activeShortcutContexts))
    }

    private func handleShortcut(_ shortcut: KeyboardShortcut) {
        router.handle(shortcut, environment: environment)
    }
}

final class KeyCommandController: UIViewController {
    var onShortcut: ((KeyboardShortcut) -> Void)?
    private var shortcuts: [KeyboardShortcut] = []
    private var shortcutLookup: [String: KeyboardShortcut] = [:]

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        shortcuts.map(makeCommand)
    }

    func updateShortcuts(_ shortcuts: [KeyboardShortcut]) {
        self.shortcuts = shortcuts
        self.shortcutLookup = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.keySignature, $0) })
        if isFirstResponder {
            resignFirstResponder()
            becomeFirstResponder()
        }
    }

    private func makeCommand(for shortcut: KeyboardShortcut) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: shortcut.input,
            modifierFlags: shortcut.modifiers,
            action: #selector(handleCommand(_:))
        )
        command.discoverabilityTitle = shortcut.title
        return command
    }

    @objc private func handleCommand(_ command: UIKeyCommand) {
        guard let input = command.input else { return }
        let signature = "\(input)|\(command.modifierFlags.rawValue)"
        guard let shortcut = shortcutLookup[signature] else { return }
        onShortcut?(shortcut)
    }
}
#endif
