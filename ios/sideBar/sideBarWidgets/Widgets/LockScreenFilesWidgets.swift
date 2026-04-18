import SwiftUI
import WidgetKit
import sideBarShared

#if os(iOS)
// MARK: - Lock Screen File Count (Circular)

struct LockScreenFileCountWidget: Widget {
    let kind: String = "LockScreenFileCount"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FilesWidgetConfigurationIntent.self, provider: PinnedFilesProvider()) { entry in
            LockScreenFileCountView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Files Count")
        .description("Shows your pinned file count.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenFileCountView: View {
    var entry: PinnedFilesEntry

    var body: some View {
        if entry.isAuthenticated {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.data.totalCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("files")
                        .font(.system(size: 8))
                        .textCase(.uppercase)
                }
            }
            .widgetURL(entry.selection.deepLinkURL)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "doc")
            }
        }
    }
}

// MARK: - Lock Screen File Preview (Rectangular)

struct LockScreenFilePreviewWidget: Widget {
    let kind: String = "LockScreenFilePreview"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FilesWidgetConfigurationIntent.self, provider: PinnedFilesProvider()) { entry in
            LockScreenFilePreviewView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Files")
        .description("Shows your pinned files.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenFilePreviewView: View {
    var entry: PinnedFilesEntry

    var body: some View {
        if !entry.isAuthenticated {
            LockScreenSignedOutRow(iconSystemName: "doc")
        } else if entry.data.files.isEmpty {
            HStack {
                Image(systemName: entry.selection.emptyStateSystemImage)
                Text(entry.selection.lockScreenEmptyLabel)
                    .font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.data.files.prefix(2)) { file in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 8))
                        Text(displayName(for: file))
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

    private func displayName(for file: WidgetFile) -> String {
        let name = file.filename
        guard let dotIndex = name.lastIndex(of: ".") else { return name }
        return String(name[..<dotIndex])
    }
}

// MARK: - Lock Screen Inline

struct LockScreenFilesInlineWidget: Widget {
    let kind: String = "LockScreenFilesInline"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FilesWidgetConfigurationIntent.self, provider: PinnedFilesProvider()) { entry in
            LockScreenFilesInlineView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Files Inline")
        .description("Shows pinned file count inline on lock screen.")
        .supportedFamilies([.accessoryInline])
    }
}

struct LockScreenFilesInlineView: View {
    var entry: PinnedFilesEntry

    var body: some View {
        if entry.isAuthenticated {
            if entry.data.totalCount == 0 {
                Label(entry.selection.lockScreenEmptyLabel, systemImage: entry.selection.emptyStateSystemImage)
            } else {
                Label(
                    "\(entry.data.totalCount) pinned file\(entry.data.totalCount == 1 ? "" : "s")",
                    systemImage: "doc.fill"
                )
            }
        } else {
            Label("sideBar", systemImage: "doc")
        }
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    LockScreenFileCountWidget()
} timeline: {
    PinnedFilesProvider.previewEntry(for: .accessoryCircular, selection: .all)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenFilePreviewWidget()
} timeline: {
    PinnedFilesProvider.previewEntry(for: .accessoryRectangular, selection: .all)
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenFilesInlineWidget()
} timeline: {
    PinnedFilesProvider.previewEntry(for: .accessoryInline, selection: .all)
}
#endif
