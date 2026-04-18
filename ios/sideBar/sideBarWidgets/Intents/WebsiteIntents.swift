import AppIntents
import Foundation
import sideBarShared

// MARK: - Widget Configuration

enum WebsiteWidgetScope: String, AppEnum {
    case all
    case domain

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Website Scope")
    static var caseDisplayRepresentations: [WebsiteWidgetScope: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "All saved websites"),
        .domain: DisplayRepresentation(title: "Domain")
    ]
}

enum WebsiteWidgetSelection: Equatable, Sendable {
    case all
    case domain(String)

    var headerTitle: String {
        switch self {
        case .all:
            return "Websites"
        case .domain(let domain):
            return domain
        }
    }

    var deepLinkURL: URL {
        URL(string: "sidebar://websites")!
    }

    func filter(_ data: WidgetWebsiteData) -> WidgetWebsiteData {
        switch self {
        case .all:
            return data
        case .domain(let domain):
            let normalizedDomain = Self.normalizeDomain(domain)
            let filteredSites = data.websites.filter {
                Self.normalizeDomain($0.domain) == normalizedDomain
            }
            return WidgetWebsiteData(
                websites: filteredSites,
                totalCount: filteredSites.count,
                lastUpdated: data.lastUpdated
            )
        }
    }

    static func normalizeDomain(_ domain: String) -> String {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("www.") {
            return String(trimmed.dropFirst(4))
        }
        return trimmed
    }
}

struct WebsiteDomainEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Website Domain")
    static var defaultQuery = WebsiteDomainEntityQuery()

    let id: String
    let domain: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(domain)")
    }
}

struct WebsiteDomainEntityQuery: EntityQuery {
    func entities(for identifiers: [WebsiteDomainEntity.ID]) async throws -> [WebsiteDomainEntity] {
        let domains = try await WebsiteWidgetConfigurationCatalogClient().domains()
        let domainsById = Dictionary(uniqueKeysWithValues: domains.map { ($0.id, $0) })
        return identifiers.compactMap { id in
            domainsById[id] ?? WebsiteDomainEntity(id: id, domain: id)
        }
    }

    func suggestedEntities() async throws -> [WebsiteDomainEntity] {
        try await WebsiteWidgetConfigurationCatalogClient().domains()
    }
}

struct WebsitesWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Websites Widget"
    static var description = IntentDescription("Choose which saved websites the widget should show.")

    @Parameter(title: "Scope", default: .all)
    var scope: WebsiteWidgetScope

    @Parameter(title: "Domain")
    var domain: WebsiteDomainEntity?

    init() {
        scope = .all
    }

    init(selection: WebsiteWidgetSelection) {
        switch selection {
        case .all:
            scope = .all
        case .domain(let value):
            scope = .domain
            domain = WebsiteDomainEntity(id: value, domain: value)
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\.$scope) {
            Case(.domain) {
                Summary("Show \(\.$scope)") {
                    \.$domain
                }
            }
            DefaultCase {
                Summary("Show \(\.$scope)")
            }
        }
    }

    var selection: WebsiteWidgetSelection {
        switch scope {
        case .all:
            return .all
        case .domain:
            if let domain {
                return .domain(domain.domain)
            }
            return .all
        }
    }
}

private struct WebsiteWidgetConfigurationCatalogClient {
    private let apiClient: APIClient

    init() throws {
        apiClient = try WidgetAPIEnvironment().apiClient
    }

    func domains() async throws -> [WebsiteDomainEntity] {
        let response: WebsitesWidgetConfigurationResponse = try await apiClient.request("websites")
        let activeDomains = Set(
            response.items
                .filter { !$0.archived && $0.deletedAt == nil }
                .map { WebsiteWidgetSelection.normalizeDomain($0.domain) }
                .filter { !$0.isEmpty }
        )
        return activeDomains.sorted().map {
            WebsiteDomainEntity(id: $0, domain: $0)
        }
    }
}

private struct WebsitesWidgetConfigurationResponse: Decodable {
    let items: [WebsitesWidgetConfigurationItem]
}

private struct WebsitesWidgetConfigurationItem: Decodable {
    let domain: String
    let archived: Bool
    let deletedAt: String?
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
