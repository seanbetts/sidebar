import AppIntents
import Foundation
import sideBarShared

// MARK: - Widget Configuration

enum WebsiteWidgetScope: String, AppEnum {
    case all
    case pinned

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Website Scope")
    static var caseDisplayRepresentations: [WebsiteWidgetScope: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "All saved websites"),
        .pinned: DisplayRepresentation(title: "Pinned websites")
    ]
}

enum WebsiteWidgetSelection: Equatable, Sendable {
    case all
    case pinned

    var emptyStateContent: WidgetEmptyStateContent {
        .noSavedWebsites()
    }

    var emptyStateTitle: String {
        emptyStateContent.title
    }

    var emptyStateSubtitle: String {
        emptyStateContent.subtitle ?? ""
    }

    var emptyStateSystemImage: String {
        emptyStateContent.systemImage
    }

    var lockScreenEmptyLabel: String {
        emptyStateContent.lockScreenLabel
    }

    var headerTitle: String {
        switch self {
        case .all:
            return "Websites"
        case .pinned:
            return "Pinned"
        }
    }

    var deepLinkURL: URL {
        URL(string: "sidebar://websites")!
    }

    func filter(_ data: WidgetWebsiteData) -> WidgetWebsiteData {
        switch self {
        case .all:
            return data
        case .pinned:
            let filteredSites = data.websites.filter(\.pinned)
            return WidgetWebsiteData(
                websites: filteredSites,
                totalCount: filteredSites.count,
                lastUpdated: data.lastUpdated
            )
        }
    }
}

struct WebsitesWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Websites Widget"
    static var description = IntentDescription("Choose which saved websites the widget should show.")

    @Parameter(title: "Scope", default: .all)
    var scope: WebsiteWidgetScope

    init() {
        scope = .all
    }

    init(selection: WebsiteWidgetSelection) {
        switch selection {
        case .all:
            scope = .all
        case .pinned:
            scope = .pinned
        }
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$scope)")
    }

    var selection: WebsiteWidgetSelection {
        switch scope {
        case .all:
            return .all
        case .pinned:
            return .pinned
        }
    }
}

// MARK: - Open Websites Intent

/// Intent to open the app to the websites view
struct OpenWebsitesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Saved Websites"
    static var description = IntentDescription("Opens sideBar to your saved websites")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://websites") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Open Website Intent

/// Intent to open a specific website in the app
struct OpenWebsiteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Website"
    static var description = IntentDescription("Opens a specific saved website in sideBar")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Website ID")
    var websiteId: String

    init() {}

    init(websiteId: String) {
        self.websiteId = websiteId
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://websites/\(websiteId)") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}
