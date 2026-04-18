import AppIntents
import XCTest
@testable import sideBar

final class WidgetIntentRoutingTests: XCTestCase {
    func testAppWidgetIntentsReturnOpenResults() async throws {
        assertOpensIntent(try await AddTaskIntent().perform())
        assertOpensIntent(try await OpenTodayIntent().perform())
        assertOpensIntent(try await OpenNotesIntent().perform())
        assertOpensIntent(try await CreateNoteIntent().perform())
        assertOpensIntent(try await OpenWebsitesIntent().perform())
        assertOpensIntent(try await OpenFilesIntent().perform())
        assertOpensIntent(try await OpenScratchpadIntent().perform())
        assertOpensIntent(try await StartChatIntent().perform())
    }

    func testAddTaskIntentTargetsOpenNewTaskDeepLink() throws {
        let widgetSource = try normalizedWidgetTaskIntentsSource()
        let appSource = try normalizedSideBarAppSource()

        XCTAssertEqual(
            widgetSource.numberOfOccurrences(of: "guardleturl=URL(string:\"sidebar://tasks/new\")else"),
            1
        )
        XCTAssertEqual(
            appSource.numberOfOccurrences(of: "guardleturl=URL(string:\"sidebar://tasks/new\")else"),
            1
        )
        XCTAssertFalse(widgetSource.contains("recordAddTaskIntent"))
        XCTAssertFalse(appSource.contains("recordAddTaskIntent"))
        XCTAssertFalse(appSource.contains("consumeWidgetAddTask"))
    }

    func testCreateNoteIntentTargetsOpenNewNoteDeepLink() throws {
        let widgetSource = try normalizedWidgetNoteIntentsSource()
        let appSource = try normalizedSideBarAppSource()

        XCTAssertEqual(
            widgetSource.numberOfOccurrences(of: "guardleturl=URL(string:\"sidebar://notes/new\")else"),
            1
        )
        XCTAssertEqual(
            appSource.numberOfOccurrences(of: "guardleturl=URL(string:\"sidebar://notes/new\")else"),
            1
        )
        XCTAssertFalse(widgetSource.contains("recordAddNoteIntent"))
        XCTAssertFalse(appSource.contains("recordAddNoteIntent"))
        XCTAssertFalse(appSource.contains("consumeWidgetAddNote"))
    }

    func testQuickSaveIntentAndShortcutPlumbingAreRemoved() throws {
        XCTAssertFalse(try normalizedWidgetWebsiteIntentsSource().contains("QuickSaveIntent"))
        XCTAssertFalse(try normalizedWidgetTaskIntentsSource().contains("QuickSaveIntent"))
        XCTAssertFalse(try normalizedSideBarAppSource().contains("QuickSaveIntent"))
        XCTAssertFalse(try normalizedWidgetExtensionDataManagerSource().contains("pendingQuickSaveURL"))
        XCTAssertFalse(try normalizedAppWidgetDataManagerSource().contains("pendingQuickSaveURL"))
    }

    func testPopulatedWidgetsExposeSectionWideTapTargets() throws {
        XCTAssertEqual(
            try normalizedWidgetSource(named: "PinnedNotesWidget.swift")
                .numberOfOccurrences(of: ".widgetURL(URL(string:\"sidebar://notes\"))"),
            1
        )
        XCTAssertEqual(
            try normalizedWidgetSource(named: "SavedSitesWidget.swift")
                .numberOfOccurrences(of: ".widgetURL(URL(string:\"sidebar://websites\"))"),
            1
        )
        XCTAssertEqual(
            try normalizedWidgetSource(named: "PinnedFilesWidget.swift")
                .numberOfOccurrences(of: ".widgetURL(URL(string:\"sidebar://files\"))"),
            1
        )
    }

    func testTodayTasksWidgetOptimizesSmallLayoutWhenBackgroundIsRemoved() throws {
        let source = try normalizedWidgetSource(named: "TodayTasksWidget.swift")

        XCTAssertTrue(source.contains("@Environment(\\.showsWidgetContainerBackground)varshowsWidgetContainerBackground"))
        XCTAssertTrue(source.contains("privatevarusesStandByLayout:Bool{family==.systemSmall&&!showsWidgetContainerBackground}"))
        XCTAssertTrue(source.contains("case.systemSmall:returnusesStandByLayout?2:3"))
        XCTAssertTrue(source.contains("privatevarstandByTaskListView:someView"))
    }

    func testTaskWidgetsUseConfigurableAppIntentConfiguration() throws {
        let todaySource = try normalizedWidgetSource(named: "TodayTasksWidget.swift")
        let countSource = try normalizedWidgetSource(named: "TaskCountWidget.swift")
        let lockScreenSource = try normalizedWidgetSource(named: "LockScreenWidgets.swift")
        let intentSource = try normalizedWidgetTaskIntentsSource()

        XCTAssertTrue(
            todaySource.contains(
                "AppIntentConfiguration(kind:kind,intent:TaskWidgetConfigurationIntent.self,provider:TodayTasksProvider())"
            )
        )
        XCTAssertTrue(
            countSource.contains(
                "AppIntentConfiguration(kind:kind,intent:TaskWidgetConfigurationIntent.self,provider:TodayTasksProvider())"
            )
        )
        XCTAssertTrue(
            lockScreenSource.contains(
                "AppIntentConfiguration(kind:kind,intent:TaskWidgetConfigurationIntent.self,provider:TodayTasksProvider())"
            )
        )
        XCTAssertTrue(intentSource.contains("structTaskWidgetConfigurationIntent:WidgetConfigurationIntent"))
        XCTAssertTrue(intentSource.contains("enumTaskWidgetScope:"))
    }

    func testIngestionLiveActivityUsesBrandedAppLogoInsteadOfGenericDocumentSymbol() throws {
        let source = try normalizedWidgetSource(named: "IngestionProgressLiveActivity.swift")

        XCTAssertTrue(source.contains("Image(\"AppLogo\")"))
        XCTAssertFalse(source.contains("\"doc.badge.gearshape\""))
    }

    func testIngestionLiveActivityUsesApprovedCompactStateSymbols() throws {
        let source = try normalizedWidgetSource(named: "IngestionProgressLiveActivity.swift")

        XCTAssertTrue(source.contains("case\"uploading\":return\"arrow.up.circle.fill\""))
        XCTAssertTrue(source.contains("case\"queued\":return\"clock.fill\""))
        XCTAssertTrue(source.contains("case\"validating\",\"converting\",\"extracting\":return\"gearshape.fill\""))
        XCTAssertTrue(source.contains("case\"ai_md\",\"transcribing\":return\"pencil.line\""))
        XCTAssertTrue(source.contains("case\"thumb\",\"finalizing\":return\"tray.and.arrow.down.fill\""))
        XCTAssertTrue(source.contains("case\"ready\":return\"checkmark.circle.fill\""))
        XCTAssertTrue(source.contains("case\"failed\":return\"exclamationmark.triangle.fill\""))
        XCTAssertTrue(source.contains("case\"canceled\":return\"xmark.circle.fill\""))
    }
}

private func assertOpensIntent<Result: OpensIntent>(_: Result) {}

private func normalizedWidgetTaskIntentsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try widgetSource(
        at: ["sideBarWidgets", "Intents", "TaskIntents.swift"],
        file: file,
        line: line
    )
    .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}

private func normalizedWidgetNoteIntentsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try widgetSource(
        at: ["sideBarWidgets", "Intents", "NoteIntents.swift"],
        file: file,
        line: line
    )
    .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}

private func normalizedWidgetWebsiteIntentsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try widgetSource(
        at: ["sideBarWidgets", "Intents", "WebsiteIntents.swift"],
        file: file,
        line: line
    )
    .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}

private func normalizedSideBarAppSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try widgetSource(
        at: ["sideBar", "sideBarApp.swift"],
        file: file,
        line: line
    )
    .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}

private func normalizedWidgetExtensionDataManagerSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try widgetSource(
        at: ["sideBarWidgets", "WidgetDataManager.swift"],
        file: file,
        line: line
    )
    .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}

private func normalizedAppWidgetDataManagerSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try widgetSource(
        at: ["sideBar", "Utilities", "WidgetDataManager.swift"],
        file: file,
        line: line
    )
    .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}

private func normalizedWidgetSource(
    named fileName: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try widgetSource(
        at: ["sideBarWidgets", "Widgets", fileName],
        file: file,
        line: line
    )
    .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}

private func widgetSource(
    at pathComponents: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = pathComponents.reduce(sideBarRoot) { partialURL, component in
        partialURL.appendingPathComponent(component)
    }

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(sourceURL.lastPathComponent): \(error)", file: file, line: line)
        throw error
    }
}

private extension String {
    func numberOfOccurrences(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
