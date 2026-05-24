import XCTest

final class WidgetDeepLinkRoutingSourceTests: XCTestCase {
    func testNavigationCoordinatorUsesSinglePendingSidebarDeepLinkRoute() throws {
        let normalized = try sourceFile("App/NavigationCoordinator.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("@PublishedpublicvarpendingSidebarDeepLink:URL?"))
        XCTAssertFalse(normalized.contains("pendingNewTaskDeepLink"))
        XCTAssertFalse(normalized.contains("pendingNewNoteDeepLink"))
    }

    func testAppEnvironmentDeepLinkStoresTaskAndNoteNewAsCanonicalPendingURLs() throws {
        let normalized = try sourceFile("App/AppEnvironment+DeepLink.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("pendingSidebarDeepLink=url"))
        XCTAssertFalse(normalized.contains("pendingNewTaskDeepLink"))
        XCTAssertFalse(normalized.contains("pendingNewNoteDeepLink"))
    }

    func testAppEnvironmentDeepLinkLogsDoNotExposeRoutedResourceIdentifiers() throws {
        let normalized = try sourceFile("App/AppEnvironment+DeepLink.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("logger.info(\"Deeplinktonote\")"))
        XCTAssertTrue(normalized.contains("logger.info(\"Deeplinktowebsite\")"))
        XCTAssertTrue(normalized.contains("logger.info(\"Deeplinktofile\")"))
        XCTAssertTrue(normalized.contains("logger.info(\"Deeplinktochat\")"))
        XCTAssertFalse(normalized.contains("logger.info(\"Deeplinktonote:\\(noteId,privacy:.public)"))
        XCTAssertFalse(normalized.contains("logger.info(\"Deeplinktowebsite:\\(websiteId,privacy:.public)"))
        XCTAssertFalse(normalized.contains("logger.info(\"Deeplinktofile:\\(fileId,privacy:.public)"))
        XCTAssertFalse(normalized.contains("logger.info(\"Deeplinktochat:\\(chatId,privacy:.public)"))
    }

    func testTaskAndNoteViewsConsumeSharedPendingSidebarDeepLinkRoute() throws {
        let tasksSource = try sourceFile("Views/Tasks/TasksView.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let notesSource = try sourceFile("Views/SidebarPanels/NotesPanel.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(tasksSource.contains("consumePendingSidebarDeepLink(host:\"tasks\",path:\"/new\")"))
        XCTAssertTrue(notesSource.contains("consumePendingSidebarDeepLink(host:\"notes\",path:\"/new\")"))
        XCTAssertFalse(tasksSource.contains("pendingNewTaskDeepLink"))
        XCTAssertFalse(notesSource.contains("pendingNewNoteDeepLink"))
    }
}

private func sourceFile(
    _ relativePath: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent(relativePath)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(relativePath): \(error)", file: file, line: line)
        throw error
    }
}
