import SwiftUI
import WidgetKit

// MARK: - Lock Screen Note Count (Circular)

struct LockScreenNoteCountWidget: Widget {
    let kind: String = "LockScreenNoteCount"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedNotesProvider()) { entry in
            LockScreenNoteCountView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Notes Count")
        .description("Shows your pinned note count.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenNoteCountView: View {
    var entry: PinnedNotesEntry

    var body: some View {
        if entry.isAuthenticated {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.data.totalCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("pinned")
                        .font(.system(size: 8))
                        .textCase(.uppercase)
                }
            }
            .widgetURL(URL(string: "sidebar://notes"))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "pin")
            }
        }
    }
}

// MARK: - Lock Screen Note Preview (Rectangular)

struct LockScreenNotePreviewWidget: Widget {
    let kind: String = "LockScreenNotePreview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedNotesProvider()) { entry in
            LockScreenNotePreviewView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Notes")
        .description("Shows your pinned notes.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenNotePreviewView: View {
    var entry: PinnedNotesEntry

    var body: some View {
        if !entry.isAuthenticated {
            HStack {
                Image(systemName: "pin")
                Text("Sign in to sideBar")
                    .font(.caption)
            }
        } else if entry.data.notes.isEmpty {
            HStack {
                Image(systemName: "pin")
                Text("No pinned notes")
                    .font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.data.notes.prefix(2)) { note in
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill")
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
        StaticConfiguration(kind: kind, provider: PinnedNotesProvider()) { entry in
            LockScreenNotesInlineView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Notes Inline")
        .description("Shows pinned note count inline on lock screen.")
        .supportedFamilies([.accessoryInline])
    }
}

struct LockScreenNotesInlineView: View {
    var entry: PinnedNotesEntry

    var body: some View {
        if entry.isAuthenticated {
            if entry.data.totalCount == 0 {
                Label("No pinned notes", systemImage: "pin")
            } else {
                Label(
                    "\(entry.data.totalCount) pinned",
                    systemImage: "pin.fill"
                )
            }
        } else {
            Label("sideBar", systemImage: "pin")
        }
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    LockScreenNoteCountWidget()
} timeline: {
    PinnedNotesEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenNotePreviewWidget()
} timeline: {
    PinnedNotesEntry.placeholder
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenNotesInlineWidget()
} timeline: {
    PinnedNotesEntry.placeholder
}
