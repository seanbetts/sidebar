import AppIntents
import SwiftUI
import WidgetKit

struct RecentNotesWidget: Widget {
    let kind: String = "RecentNotesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentNotesProvider()) { entry in
            RecentNotesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Notes")
        .description("View and access your recent notes at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget View

struct RecentNotesWidgetView: View {
    var entry: RecentNotesEntry

    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if !entry.isAuthenticated {
            notAuthenticatedView
        } else if entry.data.notes.isEmpty {
            emptyStateView
        } else {
            noteListView
        }
    }

    // MARK: - Note List View

    private var noteListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Link(destination: URL(string: "sidebar://notes")!) {
                VStack(alignment: .leading, spacing: 12) {
                    headerView
                    notesList
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            HStack {
                if showMoreIndicator {
                    moreNotesIndicator
                }
                Spacer()
                createNoteButton
            }
        }
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var topPadding: CGFloat {
        // Medium widget needs more top padding to visually match large widget
        // because it has fewer content rows and more empty space below
        switch family {
        case .systemSmall: return 0
        case .systemMedium: return 12
        case .systemLarge: return 4
        default: return 0
        }
    }

    private var headerView: some View {
        HStack(spacing: 6) {
            Image("AppLogo")
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text("Notes")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            if entry.data.totalCount > 0 {
                Text("\(entry.data.totalCount)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
            }
        }
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: noteSpacing) {
            ForEach(displayedNotes) { note in
                NoteRowView(note: note, compact: isCompact)
            }
        }
    }

    private var displayedNotes: [WidgetNote] {
        Array(entry.data.notes.prefix(maxNotes))
    }

    private var maxNotes: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        case .systemLarge: return 8
        default: return 3
        }
    }

    private var noteSpacing: CGFloat {
        switch family {
        case .systemSmall: return 6
        case .systemMedium: return 6
        case .systemLarge: return 10
        default: return 6
        }
    }

    private var isCompact: Bool {
        family == .systemSmall
    }

    private var showMoreIndicator: Bool {
        entry.data.totalCount > displayedNotes.count
    }

    private var moreNotesIndicator: some View {
        Text("+\(entry.data.totalCount - displayedNotes.count) more")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var createNoteButton: some View {
        Group {
            if #available(iOS 17.0, *) {
                Button(intent: CreateNoteIntent()) {
                    createNoteButtonContent
                }
            } else {
                Link(destination: URL(string: "sidebar://notes/new")!) {
                    createNoteButtonContent
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var buttonSize: CGFloat {
        family == .systemSmall ? 20 : 24
    }

    @ViewBuilder
    private var createNoteButtonContent: some View {
        switch renderingMode {
        case .fullColor:
            if colorScheme == .dark {
                Image(systemName: "plus")
                    .font(.system(size: buttonSize * 0.5, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(.white))
            } else {
                Image(systemName: "plus")
                    .font(.system(size: buttonSize * 0.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(.black))
            }
        case .accented:
            ZStack {
                Circle()
                    .fill(.fill.tertiary)
                    .frame(width: buttonSize, height: buttonSize)
                Image(systemName: "plus")
                    .font(.system(size: buttonSize * 0.5, weight: .bold))
                    .widgetAccentable()
            }
        default:
            Image(systemName: "plus")
                .font(.system(size: buttonSize * 0.5, weight: .bold))
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(.fill.tertiary))
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Text("No notes yet")
                .font(.headline)
            Text("Create your first note")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                createNoteButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "sidebar://notes"))
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Sign in to sideBar")
                .font(.headline)
            Text("to see your notes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Note Row View

struct NoteRowView: View {
    let note: WidgetNote
    let compact: Bool

    var body: some View {
        Link(destination: URL(string: "sidebar://notes/\(note.path)")!) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: compact ? 14 : 16))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.name)
                        .font(compact ? .caption : .subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if !compact, let preview = note.contentPreview, !preview.isEmpty {
                        Text(preview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    RecentNotesWidget()
} timeline: {
    RecentNotesEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    RecentNotesWidget()
} timeline: {
    RecentNotesEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    RecentNotesWidget()
} timeline: {
    RecentNotesEntry.placeholder
}

#Preview("Empty", as: .systemMedium) {
    RecentNotesWidget()
} timeline: {
    RecentNotesEntry(date: Date(), data: .empty, isAuthenticated: true)
}

#Preview("Not Authenticated", as: .systemMedium) {
    RecentNotesWidget()
} timeline: {
    RecentNotesEntry.notAuthenticated
}
