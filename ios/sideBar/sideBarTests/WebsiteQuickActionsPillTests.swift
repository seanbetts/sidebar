import XCTest
@testable import sideBar

final class WebsiteQuickActionsPillTests: XCTestCase {
    func testQuickActionPillButtonsUseTouchTargetSizedFrames() {
        XCTAssertEqual(
            WebsiteContentQuickActionsPill.controlTouchTarget,
            HeaderActionControlMetrics.chromeHeight
        )
    }

    func testQuickActionPillUsesLargerSharedIconSize() {
        XCTAssertEqual(
            WebsiteContentQuickActionsPill.controlIconSize,
            HeaderActionControlMetrics.iconFrameHeight
        )
    }

    func testQuickActionPillSourceUsesTouchTargetSizedFrames() throws {
        let normalized = try websitesMenuActionsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(".frame(width:Self.controlTouchTarget,height:Self.controlTouchTarget)")
        )
    }
}

private func websitesMenuActionsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Websites")
        .appendingPathComponent("WebsitesDetailView+MenuActions.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read WebsitesDetailView+MenuActions.swift: \(error)", file: file, line: line)
        throw error
    }
}
