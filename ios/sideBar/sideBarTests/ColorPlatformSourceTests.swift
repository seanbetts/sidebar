import XCTest

final class ColorPlatformSourceTests: XCTestCase {
    func testColorPlatformUsesUnifiedPaletteInsteadOfPlatformSpecificSurfaceSources() throws {
        let normalized = try colorPlatformSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("MacOSPalette"))
        XCTAssertFalse(normalized.contains("uiColor:.systemBackground"))
        XCTAssertFalse(normalized.contains("uiColor:.secondarySystemBackground"))
        XCTAssertFalse(normalized.contains("uiColor:.systemGroupedBackground"))
        XCTAssertFalse(normalized.contains("uiColor:.secondarySystemGroupedBackground"))
        XCTAssertFalse(normalized.contains("uiColor:.separator"))

        XCTAssertTrue(normalized.contains("privateenumAppPalette"))
        XCTAssertTrue(
            normalized.contains(
                "staticletbackground=AppDynamicColor(name:\"appBackground\",light:.white,dark:.hex0A0A0A)"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "staticletinput=AppDynamicColor(name:\"appInput\",light:.hexE5E5E5,dark:.white.opacity(0.15))"
            )
        )
    }

    func testSettingsSurfacesResolveThroughCanonicalPaletteRoles() throws {
        let normalized = try colorPlatformSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("staticvarappSettingsBackground:Color{AppPalette.muted.color}"))
        XCTAssertTrue(normalized.contains("staticvarappSettingsFormBackground:Color{AppPalette.surface.color}"))
        XCTAssertFalse(normalized.contains("uiColor:.systemGroupedBackground"))
        XCTAssertFalse(normalized.contains("uiColor:.secondarySystemGroupedBackground"))
    }

    private func colorPlatformSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sourceURL = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Common")
            .appendingPathComponent("Color+Platform.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read Color+Platform.swift: \(error)", file: file, line: line)
            throw error
        }
    }
}
