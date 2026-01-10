#if os(macOS)
import SwiftUI

struct SidebarCommands: Commands {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Chat") {
                environment.commandSelection = .chat
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Notes") {
                environment.commandSelection = .notes
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Files") {
                environment.commandSelection = .files
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button("Websites") {
                environment.commandSelection = .websites
            }
            .keyboardShortcut("4", modifiers: [.command])

            Button("Memories") {
                environment.commandSelection = .memories
            }
            .keyboardShortcut("5", modifiers: [.command])

            Button("Weather") {
                environment.commandSelection = .weather
            }
            .keyboardShortcut("6", modifiers: [.command])
        }
    }
}
#endif
