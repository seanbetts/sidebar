import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var viewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    let showsCompactStatus: Bool
    @StateObject private var editorHandle = CodeMirrorEditorHandle()
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasExternalUpdate {
                ExternalUpdateBanner(
                    onReload: viewModel.acceptExternalUpdate,
                    onKeep: viewModel.dismissExternalUpdate
                )
            }
            if !viewModel.isReadOnly {
                MarkdownFormattingToolbar(isReadOnly: viewModel.isReadOnly) { command in
                    editorHandle.applyCommand(command)
                }
            }
            ZStack(alignment: .topLeading) {
                HStack {
                    Spacer(minLength: 0)
                    CodeMirrorEditorView(
                        markdown: viewModel.content,
                        isReadOnly: viewModel.isReadOnly || !isEditing,
                        handle: editorHandle,
                        onContentChanged: viewModel.handleUserMarkdownEdit
                    )
                    .frame(maxWidth: maxContentWidth)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if !isEditing && !viewModel.isReadOnly {
                                isEditing = true
                                editorHandle.focus()
                            }
                        }
                    )
                    Spacer(minLength: 0)
                }
                if viewModel.content.isEmpty {
                    Text("Start writing...")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            if showsCompactStatus {
                SaveStatusView(editorViewModel: viewModel)
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
        }
        .onChange(of: viewModel.currentNoteId) { _, _ in
            isEditing = false
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemYellow).opacity(0.2))
    }
}
