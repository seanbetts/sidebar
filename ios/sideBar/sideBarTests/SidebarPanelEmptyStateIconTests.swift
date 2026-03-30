import XCTest

final class SidebarPanelEmptyStateIconTests: XCTestCase {
    func testChatAndNotesEmptyStatesMatchSidebarRailIcons() throws {
        let rail = try sidebarRailSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let conversations = try sidebarPanelsSource("ConversationsPanel.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let notes = try sidebarPanelsSource("NotesPanel+Helpers.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(rail.contains("case.chat:return\"bubble\""))
        XCTAssertTrue(conversations.contains("systemImage:\"bubble\""))
        XCTAssertTrue(rail.contains("case.notes:return\"text.document\""))
        XCTAssertTrue(notes.contains("systemImage:\"text.document\""))
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

private func sidebarRailSource(
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
        .appendingPathComponent("SidebarRail.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SidebarRail.swift: \(error)", file: file, line: line)
        throw error
    }
}
