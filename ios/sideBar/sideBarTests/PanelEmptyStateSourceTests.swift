import XCTest

final class PanelEmptyStateSourceTests: XCTestCase {
    func testCorePanelsUseSharedEmptyStateContentFactory() throws {
        let filesSource = try source(named: "FilesPanel.swift")
        let websitesSource = try source(named: "WebsitesPanel.swift")
        let conversationsSource = try source(named: "ConversationsPanel.swift")
        let notesSource = try source(named: "NotesPanel+Helpers.swift")

        XCTAssertTrue(filesSource.contains("EmptyStateContent.noContentYet("))
        XCTAssertTrue(filesSource.contains("EmptyStateContent.noResults("))
        XCTAssertTrue(websitesSource.contains("EmptyStateContent.noContentYet("))
        XCTAssertTrue(websitesSource.contains("EmptyStateContent.noResults("))
        XCTAssertTrue(conversationsSource.contains("EmptyStateContent.noContentYet("))
        XCTAssertTrue(conversationsSource.contains("EmptyStateContent.noResults("))
        XCTAssertTrue(notesSource.contains("EmptyStateContent.noContentYet("))
    }

    private func source(named fileName: String) throws -> String {
        let fileURL = URL(fileURLWithPath: #filePath)
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("SidebarPanels")
            .appendingPathComponent(fileName)

        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
