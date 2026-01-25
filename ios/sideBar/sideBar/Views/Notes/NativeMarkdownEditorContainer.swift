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
        .onAppear {
            loadIfNeeded()
        }
        .onChange(of: editorViewModel.currentNoteId) { _, _ in
            isEditing = false
            loadIfNeeded()
        }
        .onChange(of: nativeViewModel.hasUnsavedChanges) { _, hasChanges in
            guard hasChanges else { return }
            Task {
                await editorViewModel.syncFromNativeEditor(nativeViewModel)
            }
        }
        .onChange(of: isEditing) { _, editing in
            isTextEditorFocused = editing
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
