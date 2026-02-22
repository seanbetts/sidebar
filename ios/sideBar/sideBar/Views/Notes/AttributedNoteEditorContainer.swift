import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorContainer: View {
    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat

    var body: some View {
        // Phase 1 scaffold: dedicated V2 route and container, behavior still mirrors V1.
        NativeMarkdownEditorContainer(
            editorViewModel: editorViewModel,
            maxContentWidth: maxContentWidth
        )
    }
}
