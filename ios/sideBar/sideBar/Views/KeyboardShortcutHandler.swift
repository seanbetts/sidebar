#if os(iOS)
import SwiftUI
import UIKit
import os

struct KeyboardShortcutHandler: UIViewRepresentable {
    @EnvironmentObject private var environment: AppEnvironment
    private let registry = KeyboardShortcutRegistry.shared
    private let router = ShortcutActionRouter()

    func makeUIView(context: Context) -> KeyboardShortcutView {
        let view = KeyboardShortcutView()
        view.onShortcut = { shortcut in
            router.handle(shortcut, environment: environment)
        }
        view.updateShortcuts(registry.shortcuts(for: environment.activeShortcutContexts))
        return view
    }

    func updateUIView(_ uiView: KeyboardShortcutView, context: Context) {
        uiView.onShortcut = { shortcut in
            router.handle(shortcut, environment: environment)
        }
        uiView.updateShortcuts(registry.shortcuts(for: environment.activeShortcutContexts))
    }
}

final class KeyboardShortcutView: UIView {
    var onShortcut: ((KeyboardShortcut) -> Void)?
    private var shortcuts: [KeyboardShortcut] = []
    private var shortcutLookup: [String: KeyboardShortcut] = [:]
    private let logger = Logger(subsystem: "sideBar", category: "KeyboardShortcuts")

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let becameFirstResponder = self.becomeFirstResponder()
            #if DEBUG
            self.logger.info("KeyboardShortcutView didMoveToWindow becameFirstResponder=\(becameFirstResponder, privacy: .public)")
            #endif
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        #if DEBUG
        logger.info("KeyboardShortcutView keyCommands queried count=\(self.shortcuts.count, privacy: .public)")
        #endif
        return self.shortcuts.map(makeCommand)
    }

    func updateShortcuts(_ shortcuts: [KeyboardShortcut]) {
        if shortcuts == self.shortcuts {
            return
        }
        self.shortcuts = shortcuts
        self.shortcutLookup = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.keySignature, $0) })
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.window != nil else { return }
            let becameFirstResponder = self.becomeFirstResponder()
            #if DEBUG
            self.logger.info("KeyboardShortcutView updateShortcuts count=\(self.shortcuts.count, privacy: .public) becameFirstResponder=\(becameFirstResponder, privacy: .public)")
            #endif
        }
    }

    private func makeCommand(for shortcut: KeyboardShortcut) -> UIKeyCommand {
        let command = UIKeyCommand(
            title: shortcut.title,
            action: #selector(handleCommand(_:)),
            input: shortcut.input,
            modifierFlags: shortcut.modifiers
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
