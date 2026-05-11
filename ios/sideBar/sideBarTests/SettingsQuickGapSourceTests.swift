import XCTest

final class SettingsQuickGapSourceTests: XCTestCase {
    func testSettingsMoreRowsUseBodyFont() throws {
        let normalized = try settingsSource("SettingsMoreTabView.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".appFont(.body)"))
        XCTAssertFalse(normalized.contains(".appFont(.subheading)"))
    }

    func testStoreSkillCredentialActionFramesUseIconToken() throws {
        let normalized = try settingsSource("StoreSkillCredentialsView.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".frame(width:DesignTokens.Icon.xl,height:DesignTokens.Icon.xl)"))
        XCTAssertFalse(normalized.contains(".frame(width:30,height:30)"))
    }

    func testAdditionalSettingsSkillLabelsUseIconToken() throws {
        let normalized = try settingsSource("SettingsSections+Additional.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".frame(width:DesignTokens.Icon.md,height:DesignTokens.Icon.md)"))
        XCTAssertFalse(normalized.contains(".frame(width:18,height:18)"))
    }

    func testSettingsDebugLogoFramesUseIconToken() throws {
        let normalized = try settingsSource("SettingsSections+Utilities.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".frame(width:DesignTokens.Icon.xl,height:DesignTokens.Icon.xl)"))
        XCTAssertFalse(normalized.contains(".frame(width:32,height:32)"))
    }
}

private func settingsSource(
    _ filename: String,
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
        .appendingPathComponent(filename)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(filename): \(error)", file: file, line: line)
        throw error
    }
}
