import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorContainer: View {
    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    @EnvironmentObject var environment: AppEnvironment

    @StateObject private var nativeViewModel = NativeNoteEditorViewModel()
    @State private var loadedNoteId: String?
    @FocusState private var isTextEditorFocused: Bool
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    var body: some View {
        editorSurface
        .onAppear {
            nativeViewModel.setBaseFontSize(editorBaseFontSize)
            editorViewModel.attachNativeEditor(nativeViewModel)
            loadIfNeeded()
            applyAutosaveDelay(isOffline: environment.isOffline)
            nativeViewModel.isReadOnly = editorViewModel.isReadOnly
            isTextEditorFocused = !editorViewModel.isReadOnly
        }
        .onDisappear {
            editorViewModel.detachNativeEditor(nativeViewModel)
        }
        .onChange(of: editorViewModel.currentNoteId) { _, _ in
            nativeViewModel.setBaseFontSize(editorBaseFontSize)
            editorViewModel.setReadOnly(true)
            loadIfNeeded()
        }
        .onChange(of: nativeViewModel.hasUnsavedChanges) { _, hasChanges in
            Task { @MainActor in
                editorViewModel.setDirty(hasChanges)
            }
        }
        .onChange(of: nativeViewModel.autosaveToken) { _, _ in
            guard nativeViewModel.hasUnsavedChanges, !nativeViewModel.isReadOnly else { return }
            Task {
                await editorViewModel.syncFromNativeEditor(nativeViewModel)
            }
        }
        .onChange(of: editorViewModel.isReadOnly) { _, readOnly in
            Task { @MainActor in
                guard editorViewModel.isReadOnly == readOnly else { return }
                let shouldFocus = !readOnly
                if isTextEditorFocused != shouldFocus {
                    isTextEditorFocused = shouldFocus
                }
                nativeViewModel.isReadOnly = readOnly
            }
        }
        .onChange(of: environment.isOffline) { _, isOffline in
            applyAutosaveDelay(isOffline: isOffline)
        }
        .onChange(of: appTextSizeRaw) { _, newValue in
            Task { @MainActor in
                guard appTextSizeRaw == newValue else { return }
                let option = AppTextSizeOption.resolved(from: newValue)
                nativeViewModel.setBaseFontSize(NoteTextTypography.defaultBodyFontSize(for: option))
                nativeViewModel.updatePrefixVisibility()
            }
        }
        .onChange(of: isTextEditorFocused) { _, focused in
            // When user taps into the editor, enter edit mode.
            Task { @MainActor in
                guard isTextEditorFocused == focused else { return }
                if focused && editorViewModel.isReadOnly {
                    editorViewModel.setReadOnly(false)
                }
            }
        }
    }

    private var isEditing: Bool {
        !editorViewModel.isReadOnly
    }

    private var editorBaseFontSize: CGFloat {
        let option = AppTextSizeOption.resolved(from: appTextSizeRaw)
        return NoteTextTypography.defaultBodyFontSize(for: option)
    }

    private var editorSurface: some View {
        VStack(spacing: 0) {
            if isEditing {
                AttributedNoteFormattingToolbar(viewModel: nativeViewModel)
                Divider()
            }
            AttributedNoteEditorView(
                viewModel: nativeViewModel,
                maxContentWidth: maxContentWidth,
                isEditable: isEditing,
                onTap: isEditing ? nil : { selection in
                    guard editorViewModel.isReadOnly else { return }
                    nativeViewModel.selection = selection
                    editorViewModel.setReadOnly(false)
                }
            )
        }
        .focused($isTextEditorFocused)
        .onKeyPress(.escape) {
            if isEditing {
                editorViewModel.setReadOnly(true)
                return .handled
            }
            guard editorViewModel.currentNoteId != nil else { return .ignored }
            environment.emitShortcutAction(.closeItem)
            return .handled
        }
        .onKeyPress(.tab, phases: .down) { keyPress in
            guard isEditing else { return .ignored }
            guard !keyPress.modifiers.contains(.shift) else { return .ignored }
            return nativeViewModel.handleListDepthKeyboardShortcut(outdent: false) ? .handled : .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "\u{19}"), phases: .down) { _ in
            guard isEditing else { return .ignored }
            return nativeViewModel.handleListDepthKeyboardShortcut(outdent: true) ? .handled : .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "bB"), phases: .down) { keyPress in
            handleFormattingShortcut(.bold, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "iI"), phases: .down) { keyPress in
            handleFormattingShortcut(.italic, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "xX"), phases: .down) { keyPress in
            handleFormattingShortcut(.strikethrough, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "eE"), phases: .down) { keyPress in
            handleFormattingShortcut(.inlineCode, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "=+"), phases: .down) { keyPress in
            handleFormattingShortcut(.promoteHeading, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "-_"), phases: .down) { keyPress in
            handleFormattingShortcut(.demoteHeading, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "7&"), phases: .down) { keyPress in
            handleFormattingShortcut(.orderedList, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "8*"), phases: .down) { keyPress in
            handleFormattingShortcut(.bulletList, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "9("), phases: .down) { keyPress in
            handleFormattingShortcut(.taskList, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: ".>"), phases: .down) { keyPress in
            handleFormattingShortcut(.blockquote, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "cC"), phases: .down) { keyPress in
            handleFormattingShortcut(.codeBlock, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "hH"), phases: .down) { keyPress in
            handleFormattingShortcut(.horizontalRule, modifiers: keyPress.modifiers)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "uU"), phases: .down) { keyPress in
            handleFormattingShortcut(.suppressUnderline, modifiers: keyPress.modifiers)
        }
    }

    private func loadIfNeeded() {
        guard let noteId = editorViewModel.currentNoteId else { return }
        guard noteId != loadedNoteId else { return }
        loadedNoteId = noteId
        nativeViewModel.loadText(editorViewModel.content)
    }

    private func applyAutosaveDelay(isOffline: Bool) {
        _ = isOffline
        nativeViewModel.autosaveDelay = 1.5
    }

    private func handleFormattingShortcut(
        _ key: AttributedNoteKeyboardShortcutKey,
        modifiers: EventModifiers
    ) -> KeyPress.Result {
        guard !editorViewModel.isReadOnly else { return .ignored }
        guard let action = AttributedNoteKeyboardShortcuts.action(for: key, modifiers: modifiers) else {
            return .ignored
        }

        switch action {
        case .formatting(let formatting):
            nativeViewModel.applyFormatting(formatting)
        case .suppressSystemUnderline:
            break
        }
        return .handled
    }
}
