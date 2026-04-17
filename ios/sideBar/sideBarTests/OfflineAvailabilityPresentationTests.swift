import XCTest
@testable import sideBar

final class OfflineAvailabilityPresentationTests: XCTestCase {
    func testSharedOfflineUnavailablePlaceholderCopyIsConsistentAcrossSurfaces() {
        XCTAssertEqual(
            DetailOfflineUnavailableResource.note.title,
            "This note isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.website.title,
            "This website isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.file.title,
            "This file isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.chat.title,
            "This chat isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.taskList.title,
            "This task list isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.chat.subtitle,
            "Open it while online on this device to keep it available here."
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.note.iconName,
            AppSection.notes.iconName
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.website.iconName,
            AppSection.websites.iconName
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.file.iconName,
            AppSection.files.iconName
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.chat.iconName,
            AppSection.chat.iconName
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.taskList.iconName,
            AppSection.tasks.iconName
        )
    }

    func testNotesDetailViewUsesSharedOfflineUnavailablePlaceholder() throws {
        let normalized = try source(named: "Views/Notes/NotesDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("DetailOfflineUnavailablePlaceholder(resource:.note)"))
    }

    func testWebsitesDetailViewUsesSharedOfflineUnavailablePlaceholderAndBlocksWelcomeStateForSelection() throws {
        let normalized = try source(named: "Views/Websites/WebsitesDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("DetailOfflineUnavailablePlaceholder(resource:.website)"))
        XCTAssertTrue(normalized.contains("&&viewModel.selectedWebsiteId==nil"))
    }

    func testFilesDetailViewsUseSharedOfflineUnavailablePlaceholder() throws {
        let filesNormalized = try source(named: "Views/Files/FilesViewComponents.swift")
            .normalizedForSourceAssertions()
        let detailNormalized = try source(named: "Views/Files/IngestionDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(filesNormalized.contains("DetailOfflineUnavailablePlaceholder(resource:.file)"))
        XCTAssertTrue(detailNormalized.contains("DetailOfflineUnavailablePlaceholder(resource:.file)"))
    }

    func testTasksDetailViewUsesSharedOfflineUnavailablePlaceholder() throws {
        let normalized = try source(named: "Views/Tasks/TasksDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("DetailOfflineUnavailablePlaceholder(resource:.taskList)"))
    }

    func testTasksPanelDoesNotReplaceNavigationListWithGlobalLoadErrorPlaceholder() throws {
        let normalized = try source(named: "Views/SidebarPanels/TasksPanel.swift")
            .normalizedForSourceAssertions()

        XCTAssertFalse(normalized.contains("SidebarPanelPlaceholder(title:\"Unabletoloadtasks\""))
    }

    func testFilesPanelOnlyShowsLoadPlaceholderWhenListContentIsEmpty() throws {
        let normalized = try source(named: "Views/SidebarPanels/FilesPanel.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("}elseifletmessage=viewModel.errorMessage,viewModel.items.isEmpty{"))
    }

    func testChatViewUsesSharedOfflineUnavailablePlaceholder() throws {
        let normalized = try source(named: "Views/Chat/ChatView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("DetailOfflineUnavailablePlaceholder(resource:.chat)"))
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
