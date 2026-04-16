import XCTest
@testable import sideBar

@MainActor
final class QueuedChangeResolutionSheetTests: XCTestCase {
    func testQueuedChangeResolutionUsesDecisionSheetPanelType() {
        XCTAssertEqual(queuedChangeResolutionPanelType(), .decisionSheet)
    }

    func testQueuedChangeResolutionSheetContainsNoConflictChoiceActions() throws {
        let normalized = try queuedChangeResolutionSheetSource().normalizedForSourceAssertions()

        XCTAssertFalse(normalized.contains("KeepQueuedChange"))
        XCTAssertFalse(normalized.contains("UseServerVersion"))
        XCTAssertFalse(normalized.contains("WriteQueueConflictResolution"))
        XCTAssertTrue(normalized.contains("Button(\"Done\")"))
    }

    func testStoreSkillDetailUsesLargeInspectorPanelType() {
        XCTAssertEqual(storeSkillDetailPanelType(), .largeInspectorSheet)
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func queuedChangeResolutionSheetSource(
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
        .appendingPathComponent("Offline")
        .appendingPathComponent("QueuedChangeResolutionSheet.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read QueuedChangeResolutionSheet.swift: \(error)", file: file, line: line)
        throw error
    }
}
