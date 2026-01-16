import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var viewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    let showsCompactStatus: Bool
    @ObservedObject var editorHandle: CodeMirrorEditorHandle
    @Binding var isEditing: Bool
    @Binding var editorFrame: CGRect

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
                    .padding(.top, 12)
                    .padding(.trailing, 16)
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
            if let coords = viewModel.pendingCaretCoords {
                viewModel.pendingCaretCoords = nil
                editorHandle.setSelectionAtDeferred(x: coords.x, y: coords.y)
            }
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
            if isEditing && !viewModel.isReadOnly {
                CodeMirrorEditorView(
                    markdown: viewModel.content,
                    isReadOnly: false,
                    handle: editorHandle,
                    onContentChanged: viewModel.handleUserMarkdownEdit,
                    onEscape: {
                        isEditing = false
                    }
                )
                .frame(maxWidth: maxContentWidth)
            } else {
                ScrollView {
                    SideBarMarkdownContainer(text: viewModel.content)
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        editorFrame = proxy.frame(in: .named("appRoot"))
                    }
                    .onChange(of: proxy.size) { _, _ in
                        editorFrame = proxy.frame(in: .named("appRoot"))
                    }
            }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("appRoot"))
                .onEnded { value in
                    guard !viewModel.isReadOnly else { return }
                    let dragDistance = hypot(value.translation.width, value.translation.height)
                    let predictedDistance = hypot(
                        value.predictedEndTranslation.width,
                        value.predictedEndTranslation.height
                    )
                    guard dragDistance < 6, predictedDistance < 12 else { return }
                    if !isEditing {
                        let localX = value.location.x - editorFrame.origin.x
                        let localY = value.location.y - editorFrame.origin.y
                        viewModel.pendingCaretCoords = CGPoint(x: localX, y: localY)
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
