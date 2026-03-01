import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorContainer: View {
    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    @EnvironmentObject var environment: AppEnvironment

    @StateObject private var nativeViewModel = NativeMarkdownEditorViewModel()
    @State private var loadedNoteId: String?
    @State private var isEditing: Bool = false
    @FocusState private var isTextEditorFocused: Bool
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    var body: some View {
        Group {
            if isEditing {
                editingView
            } else {
                readOnlyView
            }
        }
        .onAppear {
            nativeViewModel.setBaseFontSize(editorBaseFontSize)
            nativeViewModel.usesInjectedListMarkers = false
            editorViewModel.attachNativeEditor(nativeViewModel)
            loadIfNeeded()
            applyAutosaveDelay(isOffline: environment.isOffline)
            nativeViewModel.isReadOnly = !isEditing
            editorViewModel.setReadOnly(!isEditing)
        }
        .onDisappear {
            editorViewModel.detachNativeEditor(nativeViewModel)
        }
        .onChange(of: editorViewModel.currentNoteId) { _, _ in
            nativeViewModel.setBaseFontSize(editorBaseFontSize)
            isEditing = false
            editorViewModel.setReadOnly(true)
            loadIfNeeded()
        }
        .onChange(of: nativeViewModel.hasUnsavedChanges) { _, hasChanges in
            editorViewModel.setDirty(hasChanges)
        }
        .onChange(of: nativeViewModel.autosaveToken) { _, _ in
            guard nativeViewModel.hasUnsavedChanges, !nativeViewModel.isReadOnly else { return }
            Task {
                await editorViewModel.syncFromNativeEditor(nativeViewModel)
            }
        }
        .onChange(of: isEditing) { _, editing in
            isTextEditorFocused = editing
            nativeViewModel.isReadOnly = !editing
            editorViewModel.setReadOnly(!editing)
        }
        .onChange(of: editorViewModel.isReadOnly) { _, readOnly in
            let editing = !readOnly
            guard isEditing != editing else { return }
            isEditing = editing
            isTextEditorFocused = editing
            nativeViewModel.isReadOnly = readOnly
        }
        .onChange(of: environment.isOffline) { _, isOffline in
            applyAutosaveDelay(isOffline: isOffline)
        }
        .onChange(of: appTextSizeRaw) { _, newValue in
            let option = AppTextSizeOption.resolved(from: newValue)
            nativeViewModel.setBaseFontSize(MarkdownTypography.defaultBodyFontSize(for: option))
            nativeViewModel.updatePrefixVisibility()
        }
        .onChange(of: isTextEditorFocused) { _, focused in
            // When user taps into the editor, enter edit mode.
            if focused && !isEditing {
                isEditing = true
            }
        }
    }

    private var editorBaseFontSize: CGFloat {
        let option = AppTextSizeOption.resolved(from: appTextSizeRaw)
        return MarkdownTypography.defaultBodyFontSize(for: option)
    }

    private var editingView: some View {
        VStack(spacing: 0) {
            AttributedNoteFormattingToolbar(viewModel: nativeViewModel)
            Divider()
            AttributedNoteEditorView(
                viewModel: nativeViewModel,
                maxContentWidth: maxContentWidth
            )
        }
        .focused($isTextEditorFocused)
        .onKeyPress(.escape) {
            guard isEditing else { return .ignored }
            isEditing = false
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

    private var readOnlyView: some View {
        AttributedNoteReadOnlyView(
            attributedContent: nativeViewModel.attributedContent,
            maxContentWidth: maxContentWidth,
            onTap: { selection in
                nativeViewModel.selection = selection
                isEditing = true
            }
        )
        .onKeyPress(.escape) {
            guard !isEditing, editorViewModel.currentNoteId != nil else { return .ignored }
            environment.emitShortcutAction(.closeItem)
            return .handled
        }
    }

    private func loadIfNeeded() {
        guard let noteId = editorViewModel.currentNoteId else { return }
        guard noteId != loadedNoteId else { return }
        loadedNoteId = noteId
        nativeViewModel.loadMarkdown(editorViewModel.content)
    }

    private func applyAutosaveDelay(isOffline: Bool) {
        _ = isOffline
        nativeViewModel.autosaveDelay = 1.5
    }

    private func handleFormattingShortcut(
        _ key: AttributedNoteKeyboardShortcutKey,
        modifiers: EventModifiers
    ) -> KeyPress.Result {
        guard isEditing else { return .ignored }
        guard let action = AttributedNoteKeyboardShortcuts.action(for: key, modifiers: modifiers) else {
            return .ignored
        }

        switch action {
        case .formatting(let formatting):
            DispatchQueue.main.async {
                nativeViewModel.applyFormatting(formatting)
            }
        case .suppressSystemUnderline:
            break
        }
        return .handled
    }
}
