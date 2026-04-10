import XCTest

final class SettingsMacSaveStatusHeaderTests: XCTestCase {
    func testSettingsViewKeepsMacHeaderHeightStableWhenSavePillAppears() throws {
        let normalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".frame(height:LayoutMetrics.appHeaderMinHeight)"))
    }

    func testSettingsViewUsesOpacityOnlyForMacSavePillTransition() throws {
        let normalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains("SettingsSaveStatusPill(state:savePillState).transition(.opacity)")
        )
        XCTAssertFalse(normalized.contains(".transition(.move(edge:.trailing).combined(with:.opacity))"))
    }

    func testSettingsViewDoesNotAnimateEntireMacSettingsTreeForSavePillChanges() throws {
        let normalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(
            normalized.contains(
                ".animation(.easeInOut(duration:DesignTokens.Animation.standard),value:savePillState)"
            )
        )
    }

    func testSettingsViewRendersMacSavePillAsTrailingOverlayInsteadOfInlineHeaderContent() throws {
        let normalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                ".overlay(alignment:.trailing){inlineSaveStatusView.padding(.trailing,settingsHeaderSavePillTrailingInset)}"
            )
        )
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
