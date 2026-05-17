import SwiftUI
import WidgetKit
import sideBarShared

#if os(iOS)
// MARK: - Lock Screen Site Count (Circular)

struct LockScreenSiteCountWidget: Widget {
    let kind: String = "LockScreenSiteCount"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WebsitesWidgetConfigurationIntent.self, provider: SavedSitesProvider()) { entry in
            LockScreenSiteCountView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Saved Websites Count")
        .description("Shows your saved website count.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenSiteCountView: View {
    var entry: SavedSitesEntry

    var body: some View {
        if entry.isAuthenticated {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.data.totalCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("sites")
                        .font(.system(size: 8))
                        .textCase(.uppercase)
                }
            }
            .widgetURL(entry.selection.deepLinkURL)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(appIcon: AppIcon.Domain.websites)
            }
        }
    }
}

// MARK: - Lock Screen Site Preview (Rectangular)

struct LockScreenSitePreviewWidget: Widget {
    let kind: String = "LockScreenSitePreview"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WebsitesWidgetConfigurationIntent.self, provider: SavedSitesProvider()) { entry in
            LockScreenSitePreviewView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Saved Websites")
        .description("Shows your saved websites.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenSitePreviewView: View {
    var entry: SavedSitesEntry

    var body: some View {
        if !entry.isAuthenticated {
            LockScreenSignedOutRow(icon: AppIcon.Domain.websites)
        } else if entry.data.websites.isEmpty {
            HStack {
                Image(appIcon: entry.selection.emptyStateAppIcon)
                Text(entry.selection.lockScreenEmptyLabel)
                    .font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.data.websites.prefix(2)) { site in
                    HStack(spacing: 4) {
                        WidgetWebsiteFaviconView(
                            site: site,
                            imageData: entry.faviconDataByWebsiteId[site.id],
                            size: 8
                        )
                        Text(site.title)
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

struct LockScreenSitesInlineWidget: Widget {
    let kind: String = "LockScreenSitesInline"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WebsitesWidgetConfigurationIntent.self, provider: SavedSitesProvider()) { entry in
            LockScreenSitesInlineView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Saved Websites Inline")
        .description("Shows saved website count inline on lock screen.")
        .supportedFamilies([.accessoryInline])
    }
}

struct LockScreenSitesInlineView: View {
    var entry: SavedSitesEntry

    var body: some View {
        if entry.isAuthenticated {
            if entry.data.totalCount == 0 {
                Label(entry.selection.lockScreenEmptyLabel, systemImage: entry.selection.emptyStateAppIcon.rawValue)
            } else {
                Label(
                    "\(entry.data.totalCount) saved website\(entry.data.totalCount == 1 ? "" : "s")",
                    systemImage: AppIcon.Domain.websites.rawValue
                )
            }
        } else {
            Label("sideBar", systemImage: AppIcon.Domain.websites.rawValue)
        }
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    LockScreenSiteCountWidget()
} timeline: {
    SavedSitesProvider.previewEntry(for: .accessoryCircular, selection: .all)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenSitePreviewWidget()
} timeline: {
    SavedSitesProvider.previewEntry(for: .accessoryRectangular, selection: .all)
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenSitesInlineWidget()
} timeline: {
    SavedSitesProvider.previewEntry(for: .accessoryInline, selection: .all)
}
#endif
