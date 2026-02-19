#if os(macOS)
import SwiftUI

struct SidebarCommands: Commands {
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(Array(AppSection.primaryNavigationSections.enumerated()), id: \.element) { index, section in
                Button(section.title) {
                    environment.commandSelection = section
                }
                .keyboardShortcut(
                    KeyEquivalent(Character(String(index + 1))),
                    modifiers: [.command]
                )
            }
        }

        CommandGroup(after: .appSettings) {
            if #available(macOS 13.0, *) {
                SettingsLink {
                    Text("Settings")
                }
                .keyboardShortcut(",", modifiers: [.command])
            } else {
                Button("Settings") {
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        CommandGroup(after: .newItem) {
            Button("Close Item") {
                guard shouldHandleCloseItem else { return }
                environment.emitShortcutAction(.closeItem)
            }
            .keyboardShortcut(.escape, modifiers: [])
        }

        CommandMenu("Tasks") {
            Button("Complete Task") {
                environment.emitShortcutAction(.completeTask)
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Button("Edit Notes") {
                environment.emitShortcutAction(.editTaskNotes)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Move Task") {
                environment.emitShortcutAction(.moveTask)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Set Due Date") {
                environment.emitShortcutAction(.setTaskDueDate)
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("Edit Repeat") {
                environment.emitShortcutAction(.setTaskRepeat)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Delete Task") {
                environment.emitShortcutAction(.deleteItem)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }

    private var shouldHandleCloseItem: Bool {
        if environment.websitesViewModel.active != nil {
            return true
        }
        if environment.notesViewModel.activeNote != nil, environment.notesEditorViewModel.isReadOnly {
            return true
        }
        return false
    }
}
#endif
