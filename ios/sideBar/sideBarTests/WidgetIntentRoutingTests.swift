import AppIntents
import XCTest
@testable import sideBar

final class WidgetIntentRoutingTests: XCTestCase {
    func testAppWidgetIntentsReturnOpenResults() async throws {
        let quickSaveIntent = QuickSaveIntent()
        quickSaveIntent.url = URL(string: "https://example.com")!

        assertOpensIntent(try await AddTaskIntent().perform())
        assertOpensIntent(try await OpenTodayIntent().perform())
        assertOpensIntent(try await OpenNotesIntent().perform())
        assertOpensIntent(try await CreateNoteIntent().perform())
        assertOpensIntent(try await OpenWebsitesIntent().perform())
        assertOpensIntent(try await quickSaveIntent.perform())
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
    }

    func testPopulatedWidgetsExposeSectionWideTapTargets() throws {
        XCTAssertEqual(
            try normalizedWidgetSource(named: "PinnedNotesWidget.swift")
                .numberOfOccurrences(of: ".widgetURL(URL(string:\"sidebar://notes\"))"),
            2
        )
        XCTAssertEqual(
            try normalizedWidgetSource(named: "SavedSitesWidget.swift")
                .numberOfOccurrences(of: ".widgetURL(URL(string:\"sidebar://websites\"))"),
            2
        )
        XCTAssertEqual(
            try normalizedWidgetSource(named: "PinnedFilesWidget.swift")
                .numberOfOccurrences(of: ".widgetURL(URL(string:\"sidebar://files\"))"),
            2
        )
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
