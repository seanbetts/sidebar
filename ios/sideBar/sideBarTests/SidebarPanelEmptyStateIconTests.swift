import XCTest
@testable import sideBar
import sideBarShared

final class SidebarPanelEmptyStateIconTests: XCTestCase {
    func testChatAndNotesEmptyStatesMatchSidebarRailIcons() throws {
        let conversations = try sidebarPanelsSource("ConversationsPanel.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let notes = try sidebarPanelsSource("NotesPanel+Helpers.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertEqual(AppSection.chat.iconName, "bubble")
        XCTAssertEqual(AppSection.chat.appIcon, AppIcon.Domain.chat)
        XCTAssertTrue(conversations.contains("icon:AppIcon.Domain.chat"))
        XCTAssertEqual(AppSection.notes.iconName, "text.document")
        XCTAssertEqual(AppSection.notes.appIcon, AppIcon.Domain.notes)
        XCTAssertTrue(notes.contains("icon:AppIcon.Domain.notes"))
    }
}

private func sidebarPanelsSource(
    _ filename: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SidebarPanels")
        .appendingPathComponent(filename)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(filename): \(error)", file: file, line: line)
        throw error
    }
}
