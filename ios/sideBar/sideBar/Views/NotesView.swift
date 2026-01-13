import SwiftUI

public struct NotesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
    }

    public var body: some View {
        NotesDetailView(viewModel: environment.notesViewModel)
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
    private let contentMaxWidth: CGFloat = 800
    @EnvironmentObject private var environment: AppEnvironment
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
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
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
            SaveStatusView(editorViewModel: environment.notesEditorViewModel)
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
        .frame(minHeight: LayoutMetrics.contentHeaderMinHeight)
    }

    @ViewBuilder
    private var content: some View {
            if viewModel.activeNote != nil {
                MarkdownEditorView(
                    viewModel: environment.notesEditorViewModel,
                    maxContentWidth: contentMaxWidth,
                    showsCompactStatus: isCompact
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

}
