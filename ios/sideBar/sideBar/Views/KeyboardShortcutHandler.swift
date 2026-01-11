#if os(iOS)
import SwiftUI
import UIKit

struct KeyboardShortcutHandler: UIViewControllerRepresentable {
    @EnvironmentObject private var environment: AppEnvironment

    func makeUIViewController(context: Context) -> KeyCommandController {
        let controller = KeyCommandController()
        controller.onCommand = handleCommand
        return controller
    }

    func updateUIViewController(_ uiViewController: KeyCommandController, context: Context) {
        uiViewController.onCommand = handleCommand
    }

    private func handleCommand(_ section: AppSection) {
        environment.commandSelection = section
    }
}

final class KeyCommandController: UIViewController {
    var onCommand: ((AppSection) -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            makeCommand(input: "1", title: "Notes", action: #selector(selectNotes)),
            makeCommand(input: "2", title: "Tasks", action: #selector(selectTasks)),
            makeCommand(input: "3", title: "Websites", action: #selector(selectWebsites)),
            makeCommand(input: "4", title: "Files", action: #selector(selectFiles)),
            makeCommand(input: "5", title: "Chat", action: #selector(selectChat)),
            makeCommand(input: ",", title: "Settings", action: #selector(selectSettings))
        ]
    }

    private func makeCommand(input: String, title: String, action: Selector) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: .command, action: action)
        command.discoverabilityTitle = title
        return command
    }

    @objc private func selectChat() {
        onCommand?(.chat)
    }

    @objc private func selectNotes() {
        onCommand?(.notes)
    }

    @objc private func selectTasks() {
        onCommand?(.tasks)
    }

    @objc private func selectFiles() {
        onCommand?(.files)
    }

    @objc private func selectWebsites() {
        onCommand?(.websites)
    }

    @objc private func selectSettings() {
        onCommand?(.settings)
    }
}
#endif
