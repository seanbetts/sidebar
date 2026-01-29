import SwiftUI
import WidgetKit

// MARK: - Lock Screen Note Count (Circular)

struct LockScreenNoteCountWidget: Widget {
    let kind: String = "LockScreenNoteCount"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentNotesProvider()) { entry in
            LockScreenNoteCountView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Note Count")
        .description("Shows your note count.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenNoteCountView: View {
    var entry: RecentNotesEntry

    var body: some View {
        if entry.isAuthenticated {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.data.totalCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("notes")
                        .font(.system(size: 8))
                        .textCase(.uppercase)
                }
            }
            .widgetURL(URL(string: "sidebar://notes"))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "doc.text")
            }
        }
    }
}

// MARK: - Lock Screen Note Preview (Rectangular)

struct LockScreenNotePreviewWidget: Widget {
    let kind: String = "LockScreenNotePreview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentNotesProvider()) { entry in
            LockScreenNotePreviewView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Notes")
        .description("Shows your most recent notes.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenNotePreviewView: View {
    var entry: RecentNotesEntry

    var body: some View {
        if !entry.isAuthenticated {
            HStack {
                Image(systemName: "doc.text")
                Text("Sign in to sideBar")
                    .font(.caption)
            }
        } else if entry.data.notes.isEmpty {
            HStack {
                Image(systemName: "doc.text")
                Text("No notes yet")
                    .font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.data.notes.prefix(2)) { note in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 8))
                        Text(note.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                if entry.data.totalCount > 2 {
                    Text("+\(entry.data.totalCount - 2) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "sidebar://notes"))
        }
    }
}

// MARK: - Lock Screen Inline

struct LockScreenNotesInlineWidget: Widget {
    let kind: String = "LockScreenNotesInline"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentNotesProvider()) { entry in
            LockScreenNotesInlineView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Notes Inline")
        .description("Shows note count inline on lock screen.")
        .supportedFamilies([.accessoryInline])
    }
}

struct LockScreenNotesInlineView: View {
    var entry: RecentNotesEntry

    var body: some View {
        if entry.isAuthenticated {
            if entry.data.totalCount == 0 {
                Label("No notes", systemImage: "doc.text")
            } else {
                Label(
                    "\(entry.data.totalCount) note\(entry.data.totalCount == 1 ? "" : "s")",
                    systemImage: "doc.text"
                )
            }
        } else {
            Label("sideBar", systemImage: "doc.text")
        }
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    LockScreenNoteCountWidget()
} timeline: {
    RecentNotesEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenNotePreviewWidget()
} timeline: {
    RecentNotesEntry.placeholder
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenNotesInlineWidget()
} timeline: {
    RecentNotesEntry.placeholder
}
