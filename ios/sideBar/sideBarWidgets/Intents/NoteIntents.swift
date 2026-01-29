import AppIntents
import WidgetKit
import os

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

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Create Note Intent

/// Intent to open the app to create a new note
struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note"
    static var description = IntentDescription("Opens sideBar to create a new note")
    static var openAppWhenRun: Bool = true
    private let logger = Logger(subsystem: "sideBar", category: "WidgetIntent")

    func perform() async throws -> some IntentResult {
        logger.info("CreateNoteIntent recording pending create note")
        WidgetDataManager.shared.recordPendingOperation(
            WidgetPendingOperation(itemId: "", action: NoteWidgetAction.addNew),
            for: .notes
        )
        return .result()
    }
}

// MARK: - Open Notes Intent

/// Intent to open the app to the notes view
struct OpenNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Notes"
    static var description = IntentDescription("Opens sideBar to your notes")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// Note: App shortcuts are combined in SideBarShortcutsProvider in TaskIntents.swift
// Only one AppShortcutsProvider is allowed per app
