import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var viewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasExternalUpdate {
                ExternalUpdateBanner(
                    onReload: viewModel.acceptExternalUpdate,
                    onKeep: viewModel.dismissExternalUpdate
                )
            }
            ZStack(alignment: .topLeading) {
                HStack {
                    Spacer(minLength: 0)
                    editorSurface
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

private struct ExternalUpdateBanner: View {
    let onReload: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text("This note was updated elsewhere.")
                .font(.subheadline)
            Spacer()
            Button("Reload", action: onReload)
            Button("Keep editing", action: onKeep)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .background(Color(.systemYellow).opacity(0.2))
    }
}
