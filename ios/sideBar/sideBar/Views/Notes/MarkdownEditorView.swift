import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var viewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    let showsCompactStatus: Bool
    @ObservedObject var editorHandle: CodeMirrorEditorHandle
    @Binding var isEditing: Bool

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
        .coordinateSpace(name: "editorSurface")
        .overlay(alignment: .topTrailing) {
            if showsCompactStatus {
                SaveStatusView(editorViewModel: viewModel)
                    .padding(.top, DesignTokens.Spacing.sm)
                    .padding(.trailing, DesignTokens.Spacing.md)
            }
        }
        .task(id: viewModel.currentNoteId) {
            // Using task(id:) instead of onChange so it fires both on appear and on change
            // Small delay to ensure sheet has dismissed and view hierarchy is stable
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await MainActor.run {
                if viewModel.wantsEditingOnNextLoad {
                    viewModel.wantsEditingOnNextLoad = false
                    isEditing = true
                    editorHandle.focus()
                }
            }
        }
        .onChange(of: viewModel.currentNoteId) { _, _ in
            // Only reset editing state when switching notes (not for wantsEditingOnNextLoad case)
            if !viewModel.wantsEditingOnNextLoad {
                isEditing = false
            }
        }
        .onChange(of: viewModel.isReadOnly) { _, newValue in
            if newValue {
                isEditing = false
            }
        }
        .onChange(of: isEditing) { _, newValue in
            guard newValue, !viewModel.isReadOnly else { return }
            editorHandle.focus()
        }
        #if os(macOS)
        .onExitCommand {
            isEditing = false
        }
        #endif
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            CodeMirrorEditorView(
                markdown: viewModel.content,
                isReadOnly: !isEditing || viewModel.isReadOnly,
                handle: editorHandle,
                onContentChanged: viewModel.handleUserMarkdownEdit,
                onEscape: {
                    isEditing = false
                },
                onRequestEdit: { point in
                    guard !viewModel.isReadOnly else { return }
                    isEditing = true
                    editorHandle.setSelectionAtDeferred(x: point.x, y: point.y)
                    editorHandle.focus()
                }
            )
            .frame(maxWidth: maxContentWidth)
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
