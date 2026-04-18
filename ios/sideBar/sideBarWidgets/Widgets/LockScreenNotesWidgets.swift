import SwiftUI
import WidgetKit
import sideBarShared

#if os(iOS)
// MARK: - Lock Screen Note Count (Circular)

struct LockScreenNoteCountWidget: Widget {
    let kind: String = "LockScreenNoteCount"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NotesWidgetConfigurationIntent.self, provider: PinnedNotesProvider()) { entry in
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
                    Text(entry.selection == .all ? "pinned" : "notes")
                        .font(.system(size: 8))
                        .textCase(.uppercase)
                }
            }
            .widgetURL(entry.selection.deepLinkURL)
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
        AppIntentConfiguration(kind: kind, intent: NotesWidgetConfigurationIntent.self, provider: PinnedNotesProvider()) { entry in
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
            LockScreenSignedOutRow(iconSystemName: "pin")
        } else if entry.data.notes.isEmpty {
            HStack {
                Image(systemName: entry.selection.emptyStateSystemImage)
                Text(entry.selection.lockScreenEmptyLabel)
                    .font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.data.notes.prefix(2)) { note in
                    HStack(spacing: 4) {
                        Image(systemName: entry.selection == .all ? "pin.fill" : "doc.text")
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
            .widgetURL(entry.selection.deepLinkURL)
        }
    }
}

// MARK: - Lock Screen Inline

struct LockScreenNotesInlineWidget: Widget {
    let kind: String = "LockScreenNotesInline"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NotesWidgetConfigurationIntent.self, provider: PinnedNotesProvider()) { entry in
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
                Label(entry.selection.lockScreenEmptyLabel, systemImage: entry.selection.emptyStateSystemImage)
            } else {
                Label(
                    entry.selection == .all ? "\(entry.data.totalCount) pinned" : "\(entry.data.totalCount) notes",
                    systemImage: entry.selection == .all ? "pin.fill" : "folder"
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
    PinnedNotesProvider.previewEntry(for: .accessoryCircular, selection: .all)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenNotePreviewWidget()
} timeline: {
    PinnedNotesProvider.previewEntry(for: .accessoryRectangular, selection: .all)
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenNotesInlineWidget()
} timeline: {
    PinnedNotesProvider.previewEntry(for: .accessoryInline, selection: .all)
}
#endif
