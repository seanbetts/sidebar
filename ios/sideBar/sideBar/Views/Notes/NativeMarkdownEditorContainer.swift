import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownEditorContainer: View {
    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat

    @StateObject private var nativeViewModel = NativeMarkdownEditorViewModel()
    @State private var loadedNoteId: String?

    var body: some View {
        NativeMarkdownEditorView(
            viewModel: nativeViewModel,
            maxContentWidth: maxContentWidth
        ) { _ in }
        .onAppear {
            nativeViewModel.isReadOnly = false
            loadIfNeeded()
        }
        .onChange(of: editorViewModel.currentNoteId) { _, _ in
            loadIfNeeded()
        }
        .onChange(of: nativeViewModel.hasUnsavedChanges) { _, hasChanges in
            guard hasChanges else { return }
            Task {
                await editorViewModel.syncFromNativeEditor(nativeViewModel)
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
