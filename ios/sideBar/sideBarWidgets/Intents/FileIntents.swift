import AppIntents
import WidgetKit

// MARK: - Open Files Intent

/// Intent to open the app to the files view
struct OpenFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Files"
    static var description = IntentDescription("Opens sideBar to your files")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Open File Intent

/// Intent to open a specific file in the app
struct OpenFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Open File"
    static var description = IntentDescription("Opens a specific file in sideBar")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "File ID")
    var fileId: String

    init() {}

    init(fileId: String) {
        self.fileId = fileId
    }

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
