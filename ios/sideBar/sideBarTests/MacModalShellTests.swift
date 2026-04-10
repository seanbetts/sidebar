import SwiftUI
import XCTest
@testable import sideBar

final class MacModalShellTests: XCTestCase {
    func testMacModalShellUsesSharedModalChrome() {
        XCTAssertEqual(MacModalShell<EmptyView>.chromeKind, .modalShell)
    }

    func testEditorSheetUsesEditorMinimumWidth() {
        XCTAssertEqual(MacModalShell<EmptyView>.minimumWidth(for: .editorSheet), 640)
    }

    func testLargeInspectorUsesExpandedMaximumWidth() {
        XCTAssertEqual(MacModalShell<EmptyView>.maximumWidth(for: .largeInspectorSheet), 1_120)
    }

    func testSettingsMacModalDefersChromeToMacModalShell() throws {
        let normalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("MacModalShell(type:settingsMacPresentationPanelType())"))
        XCTAssertFalse(normalized.contains(".clipShape(RoundedRectangle(cornerRadius:28,style:.continuous))"))
        XCTAssertFalse(normalized.contains("Color.white.opacity(0.18)"))
        XCTAssertFalse(normalized.contains(".shadow(color:.black.opacity(0.18),radius:32,y:18)"))
    }
}

private func settingsViewSource(
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
        .appendingPathComponent("Settings")
        .appendingPathComponent("SettingsView.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SettingsView.swift: \(error)", file: file, line: line)
        throw error
    }
}
