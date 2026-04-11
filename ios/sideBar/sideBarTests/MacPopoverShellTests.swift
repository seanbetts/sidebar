import SwiftUI
import XCTest
@testable import sideBar

final class MacPopoverShellTests: XCTestCase {
    func testMacPopoverShellUsesSharedPopoverChrome() {
        XCTAssertEqual(MacPopoverShell<EmptyView>.chromeKind, .popoverShell)
    }

    func testMacPopoverShellClearsSystemPresentationBackground() throws {
        let normalized = try macPopoverShellSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".presentationBackground(.clear)"))
    }

    func testCompactPopoverUsesCompactMinimumWidth() {
        XCTAssertEqual(MacPopoverShell<EmptyView>.minimumWidth(for: .compactPopover), 280)
    }

    func testEditorPopoverUsesWideMaximumWidth() {
        XCTAssertEqual(MacPopoverShell<EmptyView>.maximumWidth(for: .editorSheet), 640)
    }
}

private func macPopoverShellSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Design")
        .appendingPathComponent("Components")
        .appendingPathComponent("MacPopoverShell.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read MacPopoverShell.swift: \(error)", file: file, line: line)
        throw error
    }
}
