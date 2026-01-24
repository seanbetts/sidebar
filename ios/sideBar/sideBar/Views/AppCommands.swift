#if os(macOS)
import SwiftUI

struct SidebarCommands: Commands {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Notes") {
                environment.commandSelection = .notes
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Tasks") {
                environment.commandSelection = .tasks
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Websites") {
                environment.commandSelection = .websites
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button("Files") {
                environment.commandSelection = .files
            }
            .keyboardShortcut("4", modifiers: [.command])

            Button("Chat") {
                environment.commandSelection = .chat
            }
            .keyboardShortcut("5", modifiers: [.command])
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
}
#endif
