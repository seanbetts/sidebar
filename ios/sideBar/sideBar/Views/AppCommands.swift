#if os(macOS)
import SwiftUI

struct SidebarCommands: Commands {
    @ObservedObject private var environment: AppEnvironment

    init(environment: AppEnvironment) {
        _environment = ObservedObject(wrappedValue: environment)
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                environment.presentMacSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        if environment.isMacSettingsPresented {
            CommandGroup(after: .appSettings) {
                Button("Close Settings") {
                    environment.dismissMacSettings()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        } else {
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
                    Menu("Text Style") {
                        Button("Body") {
                            environment.notesRuntime.editorViewModel.setTextStyle(.body)
                        }
                        .keyboardShortcut("b", modifiers: [.command, .shift])
                        .disabled(!canApplyTextStyle(.body))

                        Button("Title") {
                            environment.notesRuntime.editorViewModel.setTextStyle(.title)
                        }
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                        .disabled(!canApplyTextStyle(.title))

                        Button("Heading") {
                            environment.notesRuntime.editorViewModel.setTextStyle(.heading)
                        }
                        .keyboardShortcut("h", modifiers: [.command, .shift])
                        .disabled(!canApplyTextStyle(.heading))

                        Button("Subheading") {
                            environment.notesRuntime.editorViewModel.setTextStyle(.subheading)
                        }
                        .keyboardShortcut("j", modifiers: [.command, .shift])
                        .disabled(!canApplyTextStyle(.subheading))
                    }

                    Menu("Inline") {
                        Toggle("Bold", isOn: formattingBinding(.bold))
                            .keyboardShortcut("b", modifiers: [.command])
                            .disabled(!canFormatNotes)

                        Toggle("Italic", isOn: formattingBinding(.italic))
                            .keyboardShortcut("i", modifiers: [.command])
                            .disabled(!canFormatNotes)

                        Toggle("Underline", isOn: formattingBinding(.underline))
                            .keyboardShortcut("u", modifiers: [.command])
                            .disabled(!canFormatNotes)

                        Toggle("Strikethrough", isOn: formattingBinding(.strikethrough))
                            .keyboardShortcut("x", modifiers: [.command, .shift])
                            .disabled(!canFormatNotes)

                        Toggle("Inline Code", isOn: formattingBinding(.inlineCode))
                            .disabled(!canFormatNotes)
                    }
                }
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
        let editorViewModel = environment.notesRuntime.editorViewModel
        return editorViewModel.isEditingNote && editorViewModel.canApplyFormattingCommands()
    }

    @available(macOS 26.0, *)
    private func canApplyTextStyle(_ style: NoteTextStyle) -> Bool {
        guard canFormatNotes else { return false }
        return environment.notesRuntime.editorViewModel.canApplyTextStyle(style)
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
