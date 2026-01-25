import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownEditorContainer: View {
    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat

    @StateObject private var nativeViewModel = NativeMarkdownEditorViewModel()
    @State private var loadedNoteId: String?
    @State private var isEditing: Bool = false

    var body: some View {
        Group {
            if isEditing {
                NativeMarkdownEditorView(
                    viewModel: nativeViewModel,
                    maxContentWidth: maxContentWidth
                ) { _ in }
            } else {
                ScrollView {
                    SideBarMarkdownContainer(text: editorViewModel.content)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isEditing = true
                        }
                }
            }
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
    }

    private func loadIfNeeded() {
        guard let noteId = editorViewModel.currentNoteId else { return }
        guard noteId != loadedNoteId else { return }
        loadedNoteId = noteId
        nativeViewModel.loadMarkdown(editorViewModel.content)
    }
}
