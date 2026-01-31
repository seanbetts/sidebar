import AppIntents
import SwiftUI
import WidgetKit

struct PinnedFilesWidget: Widget {
    let kind: String = "PinnedFilesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedFilesProvider()) { entry in
            PinnedFilesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Files")
        .description("View and access your pinned files.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget View

struct PinnedFilesWidgetView: View {
    var entry: PinnedFilesEntry

    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if !entry.isAuthenticated {
            notAuthenticatedView
        } else if entry.data.files.isEmpty {
            emptyStateView
        } else {
            fileListView
        }
    }

    // MARK: - File List View

    private var fileListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Link(destination: URL(string: "sidebar://files")!) {
                VStack(alignment: .leading, spacing: 12) {
                    headerView
                    filesList
                }
            }
            .buttonStyle(.plain)
            if family == .systemLarge {
                Spacer(minLength: 0)
            }
            HStack {
                if showMoreIndicator {
                    moreFilesIndicator
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
                .frame(width: family == .systemSmall ? 16 : 18, height: family == .systemSmall ? 16 : 18)
            Text("Files")
                .font(family == .systemSmall ? .subheadline : .headline)
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

    private var filesList: some View {
        VStack(alignment: .leading, spacing: fileSpacing) {
            ForEach(displayedFiles) { file in
                FileRowView(file: file, compact: isCompact)
            }
        }
    }

    private var displayedFiles: [WidgetFile] {
        Array(entry.data.files.prefix(maxFiles))
    }

    private var maxFiles: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        case .systemLarge: return 8
        default: return 3
        }
    }

    private var fileSpacing: CGFloat {
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
        entry.data.totalCount > displayedFiles.count
    }

    private var moreFilesIndicator: some View {
        Text("+\(entry.data.totalCount - displayedFiles.count) more")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Image(systemName: "pin")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Text("No pinned files")
                .font(.headline)
            Text("Pin a file to see it here")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "sidebar://files"))
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Sign in to sideBar")
                .font(.headline)
            Text("to see your files")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let file: WidgetFile
    let compact: Bool

    private var fileURL: URL {
        URL(string: "sidebar://files/\(file.id)") ?? URL(string: "sidebar://files")!
    }

    private var iconName: String {
        guard let category = file.category else { return "folder" }
        switch category.lowercased() {
        case "documents": return "doc.text"
        case "images": return "photo"
        case "audio": return "waveform"
        case "video": return "video"
        case "spreadsheets": return "tablecells"
        case "reports": return "chart.line.text.clipboard"
        case "presentations": return "rectangle.on.rectangle.angled"
        default: return "folder"
        }
    }

    private var displayName: String {
        let name = file.filename
        guard let dotIndex = name.lastIndex(of: ".") else { return name }
        return String(name[..<dotIndex])
    }

    var body: some View {
        Link(destination: fileURL) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: compact ? 14 : 16))
                    .foregroundStyle(.secondary)

                Text(displayName)
                    .font(compact ? .caption : .subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    PinnedFilesWidget()
} timeline: {
    PinnedFilesEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    PinnedFilesWidget()
} timeline: {
    PinnedFilesEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    PinnedFilesWidget()
} timeline: {
    PinnedFilesEntry.placeholder
}

#Preview("Empty", as: .systemMedium) {
    PinnedFilesWidget()
} timeline: {
    PinnedFilesEntry(date: Date(), data: .empty, isAuthenticated: true)
}

#Preview("Not Authenticated", as: .systemMedium) {
    PinnedFilesWidget()
} timeline: {
    PinnedFilesEntry.notAuthenticated
}
