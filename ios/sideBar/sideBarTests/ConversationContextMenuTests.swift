import XCTest

final class ConversationContextMenuTests: XCTestCase {
    func testConversationContextMenuIncludesShareAndExportActions() throws {
        let normalized = try conversationHelpersSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SidebarMenuItem(title:\"ShareTranscript\",systemImage:\"square.and.arrow.up\",role:nil){"))
        XCTAssertTrue(normalized.contains("SidebarMenuItem(title:\"ExportTranscript\",systemImage:\"square.and.arrow.down\",role:nil){"))
    }
}

private func conversationHelpersSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SidebarPanels")
        .appendingPathComponent("ConversationsPanelView+Helpers.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read ConversationsPanelView+Helpers.swift: \(error)", file: file, line: line)
        throw error
    }
}
