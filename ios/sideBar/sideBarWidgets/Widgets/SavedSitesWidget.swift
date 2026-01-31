import AppIntents
import SwiftUI
import WidgetKit

struct SavedSitesWidget: Widget {
    let kind: String = "SavedSitesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SavedSitesProvider()) { entry in
            SavedSitesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Websites")
        .description("Quick access to your saved websites.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget View

struct SavedSitesWidgetView: View {
    var entry: SavedSitesEntry

    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if !entry.isAuthenticated {
            notAuthenticatedView
        } else if entry.data.websites.isEmpty {
            emptyStateView
        } else {
            siteListView
        }
    }

    // MARK: - Site List View

    private var siteListView: some View {
        WidgetListLayout(family: family) {
            WidgetHeaderView(
                title: "Websites",
                totalCount: entry.data.totalCount,
                destination: URL(string: "sidebar://websites")!,
                reduceTitleForSmall: true,
                family: family
            )
        } list: {
            sitesList
        } footer: {
            HStack {
                if showMoreIndicator {
                    moreSitesIndicator
                }
                Spacer()
            }
        }
    }

    private var sitesList: some View {
        VStack(alignment: .leading, spacing: siteSpacing) {
            ForEach(displayedSites) { site in
                SiteRowView(site: site, compact: isCompact, showSubtitle: showSubtitle)
            }
        }
    }

    private var displayedSites: [WidgetWebsite] {
        Array(entry.data.websites.prefix(maxSites))
    }

    private var maxSites: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        case .systemLarge: return 8
        default: return 3
        }
    }

    private var siteSpacing: CGFloat {
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

    private var showSubtitle: Bool {
        family == .systemLarge
    }

    private var showMoreIndicator: Bool {
        entry.data.totalCount > displayedSites.count
    }

    private var moreSitesIndicator: some View {
        Text("+\(entry.data.totalCount - displayedSites.count) more")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Text("No saved sites")
                .font(.headline)
            Text("Save a site to see it here")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "sidebar://websites"))
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Sign in to sideBar")
                .font(.headline)
            Text("to see your websites")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Site Row View

struct SiteRowView: View {
    let site: WidgetWebsite
    let compact: Bool
    let showSubtitle: Bool

    private var siteURL: URL {
        URL(string: "sidebar://websites/\(site.id)") ?? URL(string: "sidebar://websites")!
    }

    var body: some View {
        Link(destination: siteURL) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: compact ? 14 : 16))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(site.title)
                        .font(compact ? .caption : .subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if showSubtitle {
                        Text(site.domain)
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
    SavedSitesWidget()
} timeline: {
    SavedSitesEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    SavedSitesWidget()
} timeline: {
    SavedSitesEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    SavedSitesWidget()
} timeline: {
    SavedSitesEntry.placeholder
}

#Preview("Empty", as: .systemMedium) {
    SavedSitesWidget()
} timeline: {
    SavedSitesEntry(date: Date(), data: .empty, isAuthenticated: true)
}

#Preview("Not Authenticated", as: .systemMedium) {
    SavedSitesWidget()
} timeline: {
    SavedSitesEntry.notAuthenticated
}
