import SwiftUI
import MarkdownUI

public struct NotesView: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        NotesDetailView(viewModel: environment.notesViewModel)
    }
}

private struct NotesDetailView: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.headline)
                if let modified = viewModel.activeNote?.modified {
                    Text(formattedDate(modified))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if let note = viewModel.activeNote {
            ScrollView {
                Markdown(note.content)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if viewModel.selectedNoteId != nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlaceholderView(title: "Select a note")
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

    private func formattedDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.noteTimestamp.string(from: date)
    }
}

private extension DateFormatter {
    static let noteTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
