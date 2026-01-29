import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownEditorContainer: View {
    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat

    @StateObject private var nativeViewModel = NativeMarkdownEditorViewModel()
    @State private var loadedNoteId: String?
    @State private var isEditing: Bool = false
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                NativeMarkdownEditorView(
                    viewModel: nativeViewModel,
                    maxContentWidth: maxContentWidth
                ) { _ in }
                .focused($isTextEditorFocused)
                .onKeyPress(.escape) {
                    guard isEditing else { return .ignored }
                    isEditing = false
                    return .handled
                }
            } else {
                NativeMarkdownReadOnlyView(
                    attributedContent: nativeViewModel.attributedContent,
                    maxContentWidth: maxContentWidth,
                    onTap: {
                        isEditing = true
                    }
                )
            }
        }
        .onAppear {
            editorViewModel.attachNativeEditor(nativeViewModel)
            loadIfNeeded()
            nativeViewModel.isReadOnly = !isEditing
            editorViewModel.setReadOnly(!isEditing)
        }
        .onDisappear {
            editorViewModel.detachNativeEditor(nativeViewModel)
        }
        .onChange(of: editorViewModel.currentNoteId) { _, _ in
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
        .onChange(of: isTextEditorFocused) { _, focused in
            // When user taps into the editor, enter edit mode
            if focused && !isEditing {
                isEditing = true
            }
        }
    }

    private func loadIfNeeded() {
        guard let noteId = editorViewModel.currentNoteId else { return }
        guard noteId != loadedNoteId else { return }
        loadedNoteId = noteId
        nativeViewModel.loadMarkdown(editorViewModel.content)
    }
}
