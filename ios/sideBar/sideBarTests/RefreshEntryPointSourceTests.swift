import XCTest

final class RefreshEntryPointSourceTests: XCTestCase {
    func testVisibleSectionChangesUseAppEnvironmentRefreshHelper() throws {
        let normalized = try source(named: "Views/ContentView+Lifecycle.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("Task{awaitenvironment.refreshVisibleSectionChange(to:section)}"))
    }

    func testSidebarPanelsUseManualRefreshHelper() throws {
        let tasksSource = try source(named: "Views/SidebarPanels/TasksPanel.swift")
            .normalizedForSourceAssertions()
        let notesSource = try source(named: "Views/SidebarPanels/NotesPanel+TreeArchive.swift")
            .normalizedForSourceAssertions()
        let websitesSource = try source(named: "Views/SidebarPanels/WebsitesPanel.swift")
            .normalizedForSourceAssertions()
        let filesSource = try source(named: "Views/SidebarPanels/FilesPanel.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(tasksSource.contains("awaitenvironment.refreshSectionManually(.tasks)"))
        XCTAssertTrue(notesSource.contains("awaitenvironment.refreshSectionManually(.notes)"))
        XCTAssertTrue(websitesSource.contains("awaitappEnvironment.refreshSectionManually(.websites)"))
        XCTAssertTrue(filesSource.contains("awaitappEnvironment.refreshSectionManually(.files)"))
    }

    func testChatRefreshablesUseManualRefreshHelper() throws {
        let conversationsSource = try source(named: "Views/SidebarPanels/ConversationsPanelView+Helpers.swift")
            .normalizedForSourceAssertions()
        let messageListSource = try source(named: "Views/Chat/ChatMessageListView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(conversationsSource.contains("awaitenvironment.refreshSectionManually(.chat)"))
        XCTAssertTrue(messageListSource.contains("awaitenvironment.refreshSectionManually(.chat)"))
    }

    func testPhoneSectionHelperDoesNotLoadContentDomainsDirectly() throws {
        let normalized = try source(named: "Views/ContentView+Lifecycle.swift")
            .normalizedForSourceAssertions()

        XCTAssertFalse(normalized.contains("case.notes:awaitenvironment.notesRuntime.viewModel.loadTree()"))
        XCTAssertFalse(normalized.contains("case.websites:awaitenvironment.websitesViewModel.load()"))
        XCTAssertFalse(normalized.contains("case.files:awaitenvironment.ingestionViewModel.load()"))
        XCTAssertFalse(normalized.contains("case.chat:awaitenvironment.chatViewModel.loadConversations()"))
        XCTAssertTrue(normalized.contains("case.skillsStore:"))
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func source(
    named relativePath: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
    let sourceURL = sideBarRoot.appendingPathComponent(relativePath)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(relativePath): \(error)", file: file, line: line)
        throw error
    }
}
