import XCTest
@testable import sideBar
import sideBarShared

final class EmptyStateViewTests: XCTestCase {
    func testInitializerStoresIconAndCopy() {
        let view = EmptyStateView(
            title: "No conversations",
            subtitle: "Start a new chat to begin.",
            icon: AppIcon.Skills.conversations
        )

        XCTAssertEqual(view.title, "No conversations")
        XCTAssertEqual(view.subtitle, "Start a new chat to begin.")
        XCTAssertEqual(view.icon, AppIcon.Skills.conversations)
    }

    func testWelcomeEmptyViewDoesNotShowSubtitle() throws {
        let source = try source(named: "Views/Common/ContentViewComponents.swift")

        XCTAssertTrue(source.contains("Text(\"Welcome to sideBar\")"))
        XCTAssertFalse(source.contains("Select a note, website, or file to get started"))
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
