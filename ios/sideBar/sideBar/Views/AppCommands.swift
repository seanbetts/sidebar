#if os(macOS)
import SwiftUI
import AppKit

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
            Button("Settings") {
                NSApp.sendAction(#selector(NSApplication.showSettingsWindow(_:)), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
#endif
