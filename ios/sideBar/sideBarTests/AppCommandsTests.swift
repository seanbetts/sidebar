import XCTest

final class AppCommandsTests: XCTestCase {
    func testMacFormatMenuGroupsTextStyleAndInlineCommands() throws {
        let normalized = try appCommandsSourceForFormattingTests()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("CommandMenu(\"Format\")"))
        XCTAssertTrue(normalized.contains("Menu(\"TextStyle\")"))
        XCTAssertTrue(normalized.contains("Button(\"Body\")"))
        XCTAssertTrue(normalized.contains("Button(\"Title\")"))
        XCTAssertTrue(normalized.contains("Button(\"Heading\")"))
        XCTAssertTrue(normalized.contains("Button(\"Subheading\")"))
        XCTAssertTrue(normalized.contains("Menu(\"Inline\")"))
        XCTAssertTrue(normalized.contains("Toggle(\"Bold\""))
        XCTAssertTrue(normalized.contains("Toggle(\"Italic\""))
        XCTAssertTrue(normalized.contains("Toggle(\"Underline\""))
        XCTAssertTrue(normalized.contains("Toggle(\"Strikethrough\""))
        XCTAssertTrue(normalized.contains("Toggle(\"InlineCode\""))
    }
}

private func appCommandsSourceForFormattingTests(
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
        .appendingPathComponent("AppCommands.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read AppCommands.swift: \(error)", file: file, line: line)
        throw error
    }
}
