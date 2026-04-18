import AppIntents
import SwiftUI
import WidgetKit
import sideBarShared

struct SavedSitesWidget: Widget {
    let kind: String = "SavedSitesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WebsitesWidgetConfigurationIntent.self, provider: SavedSitesProvider()) { entry in
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
                title: entry.selection.headerTitle,
                totalCount: entry.data.totalCount,
                destination: entry.selection.deepLinkURL,
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
        .widgetURL(entry.selection.deepLinkURL)
    }

    private var sitesList: some View {
        VStack(alignment: .leading, spacing: siteSpacing) {
            ForEach(displayedSites) { site in
                SiteRowView(
                    site: site,
                    faviconData: entry.faviconDataByWebsiteId[site.id],
                    compact: isCompact,
                    showSubtitle: showSubtitle
                )
            }
        }
    }

    private var displayedSites: [WidgetWebsite] {
        Array(entry.data.websites.prefix(maxSites))
    }

    private var maxSites: Int {
        Self.maxSites(for: family)
    }

    nonisolated static func maxSites(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        case .systemLarge: return 6
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
        HomeWidgetEmptyStateView(
            title: entry.selection.emptyStateTitle,
            subtitle: entry.selection.emptyStateSubtitle,
            iconSystemName: entry.selection.emptyStateSystemImage,
            destination: entry.selection.deepLinkURL
        )
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        HomeWidgetSignedOutView(content: .websites)
    }
}

// MARK: - Site Row View

struct SiteRowView: View {
    let site: WidgetWebsite
    let faviconData: Data?
    let compact: Bool
    let showSubtitle: Bool

    private var siteURL: URL {
        URL(string: "sidebar://websites/\(site.id)") ?? URL(string: "sidebar://websites")!
    }

    var body: some View {
        Link(destination: siteURL) {
            HStack(spacing: 8) {
                WidgetWebsiteFaviconView(
                    site: site,
                    imageData: faviconData,
                    size: compact ? 14 : 16
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(site.title)
                        .font(compact ? .caption : .subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if showSubtitle {
                        Text(site.displayDomain)
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
    SavedSitesProvider.previewEntry(for: .systemSmall, selection: .all)
}

#Preview("Medium", as: .systemMedium) {
    SavedSitesWidget()
} timeline: {
    SavedSitesProvider.previewEntry(for: .systemMedium, selection: .all)
}

#Preview("Large", as: .systemLarge) {
    SavedSitesWidget()
} timeline: {
    SavedSitesProvider.previewEntry(for: .systemLarge, selection: .all)
}

#Preview("Empty", as: .systemMedium) {
    SavedSitesWidget()
} timeline: {
    SavedSitesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: true,
        faviconDataByWebsiteId: [:],
        selection: .all
    )
}

#Preview("Not Authenticated", as: .systemMedium) {
    SavedSitesWidget()
} timeline: {
    SavedSitesEntry.notAuthenticated
}
