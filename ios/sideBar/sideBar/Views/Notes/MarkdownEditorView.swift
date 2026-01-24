import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var viewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack {
                Spacer(minLength: 0)
                editorSurface
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorSurface: some View {
        ScrollView {
            Text(viewModel.content)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DesignTokens.Spacing.sm)
        }
    }
}
