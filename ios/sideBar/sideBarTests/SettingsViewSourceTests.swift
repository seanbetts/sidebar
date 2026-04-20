import Foundation
import XCTest

final class SettingsViewSourceTests: XCTestCase {
    func testSettingsViewRenderSurfaceNoLongerWiresGlobalSavePill() throws {
        let settingsViewNormalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let settingsTabsNormalized = try settingsViewTabsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(settingsViewNormalized.contains("SettingsSaveStatusPill"))
        XCTAssertFalse(settingsViewNormalized.contains("saveStatusSignature"))
        XCTAssertFalse(settingsViewNormalized.contains("settingsSaveCompletionCount"))
        XCTAssertFalse(settingsViewNormalized.contains("savePillState"))
        XCTAssertFalse(settingsViewNormalized.contains("savePillState:"))
        XCTAssertFalse(settingsTabsNormalized.contains("SettingsSaveStatusPill"))
        XCTAssertFalse(settingsTabsNormalized.contains("savePillState"))
        XCTAssertFalse(settingsTabsNormalized.contains("savePillState:"))
        XCTAssertFalse(settingsTabsNormalized.contains("SettingsSavePillState"))
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

private func settingsViewTabsSource(
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
        .appendingPathComponent("SettingsView+Tabs.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SettingsView+Tabs.swift: \(error)", file: file, line: line)
        throw error
    }
}
