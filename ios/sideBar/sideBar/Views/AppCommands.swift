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
            CommandMenu("Format") {
                Toggle("Bold", isOn: formattingBinding(.bold))
                    .keyboardShortcut("b", modifiers: [.command])
                    .disabled(!canFormatNotes)

                Toggle("Italic", isOn: formattingBinding(.italic))
                    .keyboardShortcut("i", modifiers: [.command])
                    .disabled(!canFormatNotes)

                Toggle("Underline", isOn: formattingBinding(.underline))
                    .keyboardShortcut("u", modifiers: [.command])
                    .disabled(!canFormatNotes)
            }
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

    @available(macOS 26.0, *)
    private var canFormatNotes: Bool {
        environment.notesRuntime.editorViewModel.canApplyFormattingCommands()
    }

    @available(macOS 26.0, *)
    private func formattingBinding(_ formatting: NoteFormatting) -> Binding<Bool> {
        Binding(
            get: {
                guard canFormatNotes else { return false }
                return environment.notesRuntime.editorViewModel.isFormattingActive(formatting)
            },
            set: { enabled in
                guard canFormatNotes else { return }
                environment.notesRuntime.editorViewModel.setFormatting(formatting, enabled: enabled)
            }
        )
    }
}
#endif
