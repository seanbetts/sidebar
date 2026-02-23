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
            let outdent = keyPress.modifiers.contains(.shift)
            return nativeViewModel.handleListDepthKeyboardShortcut(outdent: outdent) ? .handled : .ignored
        }
    }

    private var readOnlyView: some View {
        AttributedNoteReadOnlyView(
            attributedContent: nativeViewModel.attributedContent,
            maxContentWidth: maxContentWidth,
            onTap: {
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
}
