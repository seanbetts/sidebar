import SwiftUI
import WidgetKit

// MARK: - Lock Screen Site Count (Circular)

struct LockScreenSiteCountWidget: Widget {
    let kind: String = "LockScreenSiteCount"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedSitesProvider()) { entry in
            LockScreenSiteCountView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Sites Count")
        .description("Shows your pinned site count.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenSiteCountView: View {
    var entry: PinnedSitesEntry

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
            .widgetURL(URL(string: "sidebar://websites"))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "globe")
            }
        }
    }
}

// MARK: - Lock Screen Site Preview (Rectangular)

struct LockScreenSitePreviewWidget: Widget {
    let kind: String = "LockScreenSitePreview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedSitesProvider()) { entry in
            LockScreenSitePreviewView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Sites")
        .description("Shows your pinned sites.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenSitePreviewView: View {
    var entry: PinnedSitesEntry

    var body: some View {
        if !entry.isAuthenticated {
            HStack {
                Image(systemName: "globe")
                Text("Sign in to sideBar")
                    .font(.caption)
            }
        } else if entry.data.websites.isEmpty {
            HStack {
                Image(systemName: "pin")
                Text("No pinned sites")
                    .font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.data.websites.prefix(2)) { site in
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 8))
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
            .widgetURL(URL(string: "sidebar://websites"))
        }
    }
}

// MARK: - Lock Screen Inline

struct LockScreenSitesInlineWidget: Widget {
    let kind: String = "LockScreenSitesInline"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedSitesProvider()) { entry in
            LockScreenSitesInlineView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Sites Inline")
        .description("Shows pinned site count inline on lock screen.")
        .supportedFamilies([.accessoryInline])
    }
}

struct LockScreenSitesInlineView: View {
    var entry: PinnedSitesEntry

    var body: some View {
        if entry.isAuthenticated {
            if entry.data.totalCount == 0 {
                Label("No pinned sites", systemImage: "globe")
            } else {
                Label(
                    "\(entry.data.totalCount) pinned site\(entry.data.totalCount == 1 ? "" : "s")",
                    systemImage: "globe"
                )
            }
        } else {
            Label("sideBar", systemImage: "globe")
        }
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    LockScreenSiteCountWidget()
} timeline: {
    PinnedSitesEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenSitePreviewWidget()
} timeline: {
    PinnedSitesEntry.placeholder
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenSitesInlineWidget()
} timeline: {
    PinnedSitesEntry.placeholder
}
