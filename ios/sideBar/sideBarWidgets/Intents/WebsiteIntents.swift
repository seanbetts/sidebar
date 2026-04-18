import AppIntents

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
