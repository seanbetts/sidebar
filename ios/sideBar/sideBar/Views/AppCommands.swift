#if os(macOS)
import SwiftUI

struct SidebarCommands: Commands {
    @ObservedObject private var environment: AppEnvironment

    init(environment: AppEnvironment) {
        _environment = ObservedObject(wrappedValue: environment)
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
        if #available(macOS 26.0, *) {
            TextFormattingCommands()
        }
    }

    private var shouldHandleCloseItem: Bool {
        if environment.websitesViewModel.active != nil {
            return true
        }
        if environment.notesRuntime.viewModel.activeNote != nil {
            return true
        }
        if hasCloseableAgentSurface {
            return true
        }
        return false
    }

    private var hasCloseableAgentSurface: Bool {
        let state = environment.workspaceStore.state
        if case .agentSurface(let surface) = state.primaryPane.descriptor,
           surface.capabilities.canClose {
            return true
        }
        if let secondaryPane = state.secondaryPane,
           case .agentSurface(let surface) = secondaryPane.descriptor,
           surface.capabilities.canClose {
            return true
        }
        return false
    }
}
#endif
