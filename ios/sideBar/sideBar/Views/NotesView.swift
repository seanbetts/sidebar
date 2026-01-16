import SwiftUI

public struct NotesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
    }

    public var body: some View {
        NotesDetailView(
            viewModel: environment.notesViewModel,
            editorViewModel: environment.notesEditorViewModel
        )
            #if !os(macOS)
            .navigationTitle(noteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCompact {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Note options")
                    }
                }
            }
            #endif
    }

    private var noteTitle: String {
        #if os(macOS)
        return "Notes"
        #else
        guard horizontalSizeClass == .compact else {
            return "Notes"
        }
        guard let name = environment.notesViewModel.activeNote?.name else {
            return "Notes"
        }
        if name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
        #endif
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}

private struct NotesDetailView: View {
    @ObservedObject var viewModel: NotesViewModel
    @ObservedObject var editorViewModel: NotesEditorViewModel
    private let contentMaxWidth: CGFloat = SideBarMarkdownLayout.maxContentWidth
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var editorHandle = CodeMirrorEditorHandle()
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if environment.isOffline {
                OfflineBanner()
            }
            if !isCompact {
                header
                Divider()
            }
            contentWithToolbar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 12) {
                Image(systemName: "text.document")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .layoutPriority(1)
                    .truncationMode(.tail)
                Spacer()
                SaveStatusView(editorViewModel: editorViewModel)
                Button {
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .imageScale(.medium)
                .accessibilityLabel("Note options")
            }
            .padding(16)
            .opacity(isEditingToolbarVisible ? 0 : 1)
            .allowsHitTesting(!isEditingToolbarVisible)
            if isEditingToolbarVisible {
                GeometryReader { proxy in
                    Color(.secondarySystemBackground)
                        .overlay(alignment: .center) {
                            MarkdownFormattingToolbar(isReadOnly: editorViewModel.isReadOnly, onClose: {
                                editorViewModel.isEditing = false
                            }) { command in
                                editorHandle.applyCommand(command)
                            }
                            .background(Color.clear)
                        }
                        .frame(height: proxy.size.height)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
        .animation(.easeInOut(duration: 0.2), value: editorViewModel.isEditing)
    }

    @ViewBuilder
    private var content: some View {
            if viewModel.activeNote != nil {
                MarkdownEditorView(
                    viewModel: editorViewModel,
                    maxContentWidth: contentMaxWidth,
                    showsCompactStatus: isCompact,
                    editorHandle: editorHandle,
                    isEditing: isEditingBinding,
                    editorFrame: editorFrameBinding
                )
            } else if viewModel.selectedNoteId != nil {
                if let error = viewModel.errorMessage {
                    PlaceholderView(
                        title: "Unable to load note",
                        subtitle: error,
                        actionTitle: "Retry"
                    ) {
                        guard let selectedId = viewModel.selectedNoteId else { return }
                        Task { await viewModel.loadNote(id: selectedId) }
                    }
                } else {
                    LoadingView(message: "Loading note…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                #if os(macOS)
                if viewModel.tree == nil {
                    LoadingView(message: "Loading notes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    WelcomeEmptyView()
                }
                #else
                if viewModel.tree == nil {
                    LoadingView(message: "Loading notes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PlaceholderView(
                        title: "Select a note",
                        subtitle: "Choose a note from the sidebar to start reading.",
                        iconName: "text.document"
                    )
                }
                #endif
            }
        }

    private var contentWithToolbar: some View {
        content
            .overlay(alignment: .top) {
                if isCompact && isEditingToolbarVisible {
                    GeometryReader { proxy in
                        Color(.secondarySystemBackground)
                            .overlay(alignment: .center) {
                                MarkdownFormattingToolbar(
                                    isReadOnly: editorViewModel.isReadOnly,
                                    onClose: {
                                        editorViewModel.isEditing = false
                                    }
                                ) { command in
                                    editorHandle.applyCommand(command)
                                }
                                .background(Color.clear)
                            }
                            .frame(height: min(proxy.size.height, LayoutMetrics.contentHeaderMinHeight))
                            .transition(.opacity)
                            .zIndex(1)
                    }
                    .frame(height: LayoutMetrics.contentHeaderMinHeight)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: editorViewModel.isEditing)
    }

    private var displayTitle: String {
        guard let name = viewModel.activeNote?.name else {
            return "Notes"
        }
        if name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var isEditingToolbarVisible: Bool {
        editorViewModel.isEditing && !editorViewModel.isReadOnly
    }

    private var isEditingBinding: Binding<Bool> {
        Binding(
            get: { editorViewModel.isEditing },
            set: { editorViewModel.isEditing = $0 }
        )
    }

    private var editorFrameBinding: Binding<CGRect> {
        Binding(
            get: { editorViewModel.editorFrame },
            set: { editorViewModel.editorFrame = $0 }
        )
    }

}
