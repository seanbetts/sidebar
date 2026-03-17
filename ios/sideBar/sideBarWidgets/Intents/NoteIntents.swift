import AppIntents
import WidgetKit
import os
import sideBarShared

// MARK: - Open Note Intent

/// Intent to open a specific note in the app
struct OpenNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Note"
    static var description = IntentDescription("Opens a specific note in sideBar")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Note Path")
    var notePath: String

    init() {}

    init(notePath: String) {
        self.notePath = notePath
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        let encodedPath = notePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? notePath
        guard let url = URL(string: "sidebar://notes/\(encodedPath)") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Create Note Intent

/// Intent to open the app to create a new note
struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note"
    static var description = IntentDescription("Opens sideBar to create a new note")
    static var openAppWhenRun: Bool = true
    private let logger = Logger(subsystem: "sideBar", category: "WidgetIntent")

    func perform() async throws -> some IntentResult & OpensIntent {
        logger.info("CreateNoteIntent recording pending create note")
        WidgetDataManager.shared.recordAddNoteIntent()
        guard let url = URL(string: "sidebar://notes") else {
            logger.error("CreateNoteIntent failed: invalid deep link URL")
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Open Notes Intent

/// Intent to open the app to the notes view
struct OpenNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Notes"
    static var description = IntentDescription("Opens sideBar to your notes")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://notes") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// Note: App shortcuts are combined in SideBarShortcutsProvider in TaskIntents.swift
// Only one AppShortcutsProvider is allowed per app
