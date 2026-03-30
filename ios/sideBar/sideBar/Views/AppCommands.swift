import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SidebarCommands: Commands {
    @ObservedObject private var environment: AppEnvironment
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    init(environment: AppEnvironment) {
        _environment = ObservedObject(wrappedValue: environment)
    }

    var body: some Commands {
        #if os(macOS)
        // SwiftUI's CommandsBuilder rejects `_ = ...` here, but `let _ = ...`
        // preserves the early bridge installation needed for macOS launch recovery.
        // swiftlint:disable redundant_discardable_let
        let _ = installMacMainWindowOpenActionIfNeeded()
        // swiftlint:enable redundant_discardable_let
        #endif
        notesFormatCommands

        #if os(macOS)
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

            if let sectionCommandContext = Self.macSectionCommandContext(
                focusedSection: environment.focusedSection,
                activeSection: environment.activeSection
            ) {
                sectionCommandMenu(for: sectionCommandContext)
            }
        }
        #endif
    }

    #if os(macOS)
    private func installMacMainWindowOpenActionIfNeeded() {
        MacMainWindowSceneBridge.install {
            openWindow(id: MacWindowConfiguration.mainWindowID)
        }
    }
    #endif

    static func macSectionCommandContext(
        focusedSection: AppSection?,
        activeSection: AppSection?
    ) -> AppSection? {
        if let focusedSection, isSupportedMacSectionCommandContext(focusedSection) {
            return focusedSection
        }
        if let activeSection, isSupportedMacSectionCommandContext(activeSection) {
            return activeSection
        }
        return nil
    }

    private static func isSupportedMacSectionCommandContext(_ section: AppSection) -> Bool {
        switch section {
        case .chat, .notes, .websites, .files, .tasks:
            return true
        case .skillsStore, .settings:
            return false
        }
    }

    @CommandsBuilder
    private func sectionCommandMenu(for section: AppSection) -> some Commands {
        switch section {
        case .chat:
            chatCommandMenu
        case .notes:
            notesCommandMenu
        case .websites:
            websitesCommandMenu
        case .files:
            filesCommandMenu
        case .tasks:
            tasksCommandMenu
        case .skillsStore, .settings:
            CommandMenu(section.title) {
            }
        }
    }

    @CommandsBuilder
    private var chatCommandMenu: some Commands {
        CommandMenu(AppSection.chat.title) {
            Button("Send Message") {
                environment.emitShortcutAction(.sendMessage)
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Button("Attach File") {
                environment.emitShortcutAction(.attachFile)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Rename Conversation") {
                environment.emitShortcutAction(.renameItem)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Delete Conversation") {
                environment.emitShortcutAction(.deleteItem)
            }
            .keyboardShortcut(.delete, modifiers: [.command])
        }
    }

    @CommandsBuilder
    private var notesCommandMenu: some Commands {
        CommandMenu(AppSection.notes.title) {
            Button("New Folder") {
                environment.emitShortcutAction(.createFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Pin Note") {
                environment.emitShortcutAction(.pinItem)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Archive Note") {
                environment.emitShortcutAction(.archiveItem)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()

            Button("Delete Note") {
                environment.emitShortcutAction(.deleteItem)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }

    @CommandsBuilder
    private var websitesCommandMenu: some Commands {
        CommandMenu(AppSection.websites.title) {
            Button("Pin Website") {
                environment.emitShortcutAction(.pinItem)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Button("Archive Website") {
                environment.emitShortcutAction(.archiveItem)
            }
            .keyboardShortcut("a", modifiers: [.command, .option])

            Button("Open in Browser") {
                environment.emitShortcutAction(.openInBrowser)
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])

            Divider()

            Button("Delete Website") {
                environment.emitShortcutAction(.deleteItem)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
        }
    }

    @CommandsBuilder
    private var filesCommandMenu: some Commands {
        CommandMenu(AppSection.files.title) {
            Button("Quick Look") {
                environment.emitShortcutAction(.quickLook)
            }
            .keyboardShortcut(" ", modifiers: [])

            Divider()

            Button("Delete File") {
                environment.emitShortcutAction(.deleteItem)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option, .shift])
        }
    }

    @CommandsBuilder
    private var tasksCommandMenu: some Commands {
        CommandMenu(AppSection.tasks.title) {
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

    @CommandsBuilder
    private var notesFormatCommands: some Commands {
        if #available(iOS 26.0, macOS 26.0, *) {
            CommandMenu("Format") {
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

                Button("Body") {
                    environment.notesRuntime.editorViewModel.setTextStyle(.body)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!canApplyTextStyle(.body))

                Divider()

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
