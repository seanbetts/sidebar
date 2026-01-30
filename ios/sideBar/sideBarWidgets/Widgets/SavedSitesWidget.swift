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
        .configurationDisplayName("Sites")
        .description("Quick access to your saved sites.")
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
        VStack(alignment: .leading, spacing: 12) {
            Link(destination: URL(string: "sidebar://websites")!) {
                VStack(alignment: .leading, spacing: 12) {
                    headerView
                    sitesList
                }
            }
            .buttonStyle(.plain)
            if family == .systemLarge {
                Spacer(minLength: 0)
            }
            HStack {
                if showMoreIndicator {
                    moreSitesIndicator
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: family == .systemLarge ? .topLeading : .top)
    }

    private var headerView: some View {
        HStack(spacing: 6) {
            Image("AppLogo")
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text("Sites")
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

    private var sitesList: some View {
        VStack(alignment: .leading, spacing: siteSpacing) {
            ForEach(displayedSites) { site in
                SiteRowView(site: site, compact: isCompact)
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
            Text("to see your sites")
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

    var body: some View {
        Link(destination: URL(string: site.url)!) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: compact ? 14 : 16))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(site.title)
                        .font(compact ? .caption : .subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if !compact {
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
