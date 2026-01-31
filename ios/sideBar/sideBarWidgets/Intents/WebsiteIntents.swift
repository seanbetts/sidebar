import AppIntents
import WidgetKit
import os

// MARK: - Open Websites Intent

/// Intent to open the app to the websites view
struct OpenWebsitesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Saved Websites"
    static var description = IntentDescription("Opens sideBar to your saved websites")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
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

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Quick Save URL Intent

/// Intent to save a URL to sideBar
struct QuickSaveIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Website"
    static var description = IntentDescription("Saves a website URL to sideBar")
    static var openAppWhenRun: Bool = true
    private let logger = Logger(subsystem: "sideBar", category: "WidgetIntent")

    @Parameter(title: "URL", description: "The website URL to save")
    var url: URL?

    init() {}

    init(url: URL) {
        self.url = url
    }

    func perform() async throws -> some IntentResult {
        guard let url else {
            logger.error("QuickSaveIntent: No URL provided")
            return .result()
        }
        logger.info("QuickSaveIntent recording pending save for URL: \(url.absoluteString)")
        WidgetDataManager.shared.recordPendingQuickSave(url: url)
        return .result()
    }
}
