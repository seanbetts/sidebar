import AppIntents
import WidgetKit

// MARK: - Open Scratchpad Intent

/// Intent to open the app to the scratchpad
struct OpenScratchpadIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Scratchpad"
    static var description = IntentDescription("Opens sideBar scratchpad for quick notes")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Start Chat Intent

/// Intent to open the app to start a new chat
struct StartChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Chat"
    static var description = IntentDescription("Opens sideBar to start a new AI chat")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Open Chat Intent

/// Intent to open a specific chat in the app
struct OpenChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Chat"
    static var description = IntentDescription("Opens a specific chat in sideBar")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Chat ID")
    var chatId: String

    init() {}

    init(chatId: String) {
        self.chatId = chatId
    }

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
