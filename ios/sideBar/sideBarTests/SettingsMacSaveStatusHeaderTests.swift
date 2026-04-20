import XCTest

final class SettingsMacSaveStatusHeaderTests: XCTestCase {
    func testSettingsViewKeepsMacHeaderHeightStableWithoutGlobalSavePill() throws {
        let normalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".frame(height:LayoutMetrics.appHeaderMinHeight)"))
    }

    func testSettingsViewDoesNotRenderMacSavePillOverlay() throws {
        let normalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("SettingsSaveStatusPill"))
        XCTAssertFalse(normalized.contains("inlineSaveStatusView"))
    }

    func testSettingsViewDoesNotTrackGlobalSavePillState() throws {
        let normalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("savePillState"))
        XCTAssertFalse(normalized.contains("saveStatusSignature"))
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
