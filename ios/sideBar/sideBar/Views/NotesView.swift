import SwiftUI
import MarkdownUI

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
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
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
        if let note = viewModel.activeNote {
            ScrollView {
                SideBarMarkdown(text: strippedContent(note: note))
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } else if viewModel.selectedNoteId != nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            #if os(macOS)
            WelcomeEmptyView()
            #else
            PlaceholderView(title: "Select a note")
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

    private func strippedContent(note: NotePayload) -> String {
        let title = displayTitle
        let trimmed = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = "# \(title)"
        if trimmed.hasPrefix(heading) {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == heading {
                let remaining = lines.dropFirst()
                let stripped = remaining.drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    .joined(separator: "\n")
                return stripped.isEmpty ? note.content : stripped
            }
        }
        return note.content
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

}
