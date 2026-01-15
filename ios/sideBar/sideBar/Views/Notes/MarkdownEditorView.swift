import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var viewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    let showsCompactStatus: Bool
    @StateObject private var editorHandle = CodeMirrorEditorHandle()
    @State private var isEditing = false
    @State private var editorFrame: CGRect = .zero

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
                if viewModel.content.isEmpty {
                    Text("Start writing...")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if isEditing && !viewModel.isReadOnly {
                    MarkdownFormattingToolbar(isReadOnly: viewModel.isReadOnly, onClose: {
                        isEditing = false
                    }) { command in
                        editorHandle.applyCommand(command)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("editorSurface"))
                    .onEnded { value in
                        guard isEditing, !viewModel.isReadOnly else { return }
                        if !editorFrame.contains(value.location) {
                            isEditing = false
                        }
                    }
            )
        }
        .coordinateSpace(name: "editorSurface")
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
        .onChange(of: viewModel.isReadOnly) { _, newValue in
            if newValue {
                isEditing = false
            }
        }
    }

    private var editorSurface: some View {
        CodeMirrorEditorView(
            markdown: viewModel.content,
            isReadOnly: viewModel.isReadOnly || !isEditing,
            handle: editorHandle,
            onContentChanged: viewModel.handleUserMarkdownEdit
        )
        .frame(maxWidth: maxContentWidth)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        editorFrame = proxy.frame(in: .named("editorSurface"))
                    }
                    .onChange(of: proxy.size) { _, _ in
                        editorFrame = proxy.frame(in: .named("editorSurface"))
                    }
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                if !isEditing && !viewModel.isReadOnly {
                    isEditing = true
                    editorHandle.focus()
                }
            }
        )
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
